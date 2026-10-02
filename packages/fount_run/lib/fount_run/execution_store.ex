defmodule FountRun.ExecutionStore do
  @moduledoc "Short PostgreSQL transactions for claims, fencing, provider reconciliation and Run accounting."

  alias Ecto.Adapters.SQL
  alias Fount.ID
  alias Fount.Writing.CanonicalJSON
  alias FountRun.{ActorContext, AnalysisLineage, ClosedMap, Persistence, Transition}

  @terminal ~w(succeeded failed cancelled fenced)

  def claim(repo, run_id, worker_id, %ActorContext{} = context, opts \\ []) do
    lease_ms = Keyword.get(opts, :lease_ms, 30_000)

    with true <- ClosedMap.uuid_string(run_id),
         true <- ClosedMap.nonempty_string(worker_id),
         true <- is_integer(lease_ms) and lease_ms >= 1_000 and lease_ms <= 3_600_000 do
      tx(repo, fn -> claim_locked(repo, run_id, worker_id, context, lease_ms) end)
      |> unwrap_claim()
    else
      _ -> {:error, :invalid_claim}
    end
  end

  def heartbeat(repo, claim, opts \\ []) when is_map(claim) do
    lease_ms = Keyword.get(opts, :lease_ms, claim["lease_ms"] || 30_000)

    if is_integer(lease_ms) and lease_ms >= 1_000 and lease_ms <= 3_600_000 do
      tx(repo, fn -> heartbeat_locked(repo, claim, lease_ms) end)
    else
      {:error, :invalid_lease}
    end
  end

  defp heartbeat_locked(repo, claim, lease_ms) do
    run = locked_run(repo, claim["run_id"])
    ensure_claim_owner!(repo, run, claim, :dispatch)

    result =
      q!(
        repo,
        "UPDATE fount_run_steps SET heartbeat_at=now(),lease_expires_at=now()+($4::bigint * interval '1 millisecond'),updated_at=now() WHERE id=$1::text::uuid AND run_id=$2::text::uuid AND lease_owner=$3 AND lease_token=$5 AND lease_expires_at>now() RETURNING lease_expires_at",
        [
          claim["step_id"],
          claim["run_id"],
          claim["lease_owner"],
          lease_ms,
          claim["fencing_token"]
        ]
      )

    if result.num_rows == 1,
      do: %{claim | "lease_ms" => lease_ms},
      else: rollback(repo, :lease_expired)
  end

  @doc "Guard used inside Core session/candidate transactions; acquires only DB row locks, never external I/O."
  def domain_guard(repo, claim, _kind, _identity) when is_map(claim) do
    row =
      one(
        repo,
        ~S"""
        SELECT r.id AS run_id,r.current_plan_version,r.current_policy_version,r.current_fencing_token,
               r.active_step_id,r.pause_requested_at,r.stop_requested_at,
               s.id AS step_id,s.plan_version,s.policy_version,s.lease_owner,s.lease_token,
               (s.lease_expires_at>now()) AS lease_live,s.status
        FROM fount_runs r JOIN fount_run_steps s ON s.run_id=r.id
        WHERE r.id=$1::text::uuid AND s.id=$2::text::uuid
        FOR SHARE OF r,s
        """,
        [claim["run_id"], claim["step_id"]]
      )

    case guard_row(row, claim, :commit) do
      :ok -> :ok
      {:error, _} = error -> error
    end
  rescue
    _error in Postgrex.Error -> {:error, :storage_error}
  end

  def link_session(repo, claim, session_id) when is_map(claim) and is_binary(session_id) do
    tx(repo, fn ->
      run = locked_run(repo, claim["run_id"])
      ensure_claim_owner!(repo, run, claim, :commit)
      step = locked_step(repo, claim["run_id"], claim["step_id"])

      cond do
        is_nil(step["session_id"]) ->
          q!(
            repo,
            "UPDATE fount_run_steps SET session_id=$3::text::uuid,status='running',updated_at=now() WHERE run_id=$1::text::uuid AND id=$2::text::uuid",
            [claim["run_id"], claim["step_id"], session_id]
          )

          session_id

        step["session_id"] == session_id ->
          session_id

        true ->
          rollback(repo, :session_link_conflict)
      end
    end)
  end

  def provider_intent(repo, claim, dispatch) when is_map(claim) and is_map(dispatch) do
    with {:ok, attrs} <- normalize_dispatch(dispatch) do
      tx(repo, fn -> provider_intent_locked(repo, claim, attrs) end)
      |> unwrap_provider_intent()
    end
  end

  def provider_dispatched(repo, claim, operation_id)
      when is_map(claim) and is_binary(operation_id) do
    tx(repo, fn ->
      run = locked_run(repo, claim["run_id"])
      ensure_claim_owner!(repo, run, claim, :dispatch)

      row =
        one(repo, "SELECT * FROM fount_run_provider_requests WHERE operation_id=$1 FOR UPDATE", [
          operation_id
        ]) ||
          rollback(repo, :provider_intent_not_found)

      cond do
        row["status"] == "intended" ->
          q!(
            repo,
            "UPDATE fount_run_provider_requests SET status='dispatched',dispatched_at=now(),updated_at=now() WHERE id=$1::text::uuid",
            [row["id"]]
          )

          q!(
            repo,
            "UPDATE fount_run_steps SET provider_dispatch_count=provider_dispatch_count+1,malformed_repair_count=malformed_repair_count+$2,transient_retry_count=transient_retry_count+$3,updated_at=now() WHERE id=$1::text::uuid",
            [
              claim["step_id"],
              bool_int(row["malformed_repair"]),
              if(row["transport_retry"] > 0, do: 1, else: 0)
            ]
          )

          :ok

        row["status"] == "succeeded" ->
          {:reuse, response_map(row["response"])}

        row["status"] in ["dispatched", "unknown"] ->
          rollback(repo, :ambiguous_provider_outcome)

        row["status"] == "failed" ->
          rollback(repo, :provider_attempt_already_failed)

        true ->
          rollback(repo, :provider_request_conflict)
      end
    end)
  end

  @doc "Records a response even after fencing so late paid output/usage remains inspectable."
  def provider_result(repo, operation_id, result)
      when is_binary(operation_id) and is_map(result) do
    tx(repo, fn -> provider_result_locked(repo, operation_id, result) end)
  end

  defp provider_result_locked(repo, operation_id, result) do
    row =
      one(repo, "SELECT * FROM fount_run_provider_requests WHERE operation_id=$1 FOR UPDATE", [
        operation_id
      ]) || rollback(repo, :provider_request_not_found)

    attrs = provider_result_attrs(result)

    cond do
      row["status"] in ["dispatched", "unknown"] ->
        save_provider_result(repo, row, operation_id, result, attrs)

      matching_provider_result?(row, result, attrs) ->
        row

      true ->
        rollback(repo, :provider_result_conflict)
    end
  end

  defp provider_result_attrs(result) do
    status = if result["status"] == "ok", do: "succeeded", else: "failed"
    response = if status == "succeeded", do: result, else: nil

    %{
      status: status,
      response: response,
      error_category: if(status == "failed", do: result["category"]),
      fingerprint: if(response, do: CanonicalJSON.hash(response)),
      usage: result["usage"] || %{}
    }
  end

  defp matching_provider_result?(row, result, attrs) do
    row["status"] == attrs.status and row["response_fingerprint"] == attrs.fingerprint and
      row["error_category"] == attrs.error_category and row["usage"] == attrs.usage and
      row["provider_request_id"] == result["id"]
  end

  defp save_provider_result(repo, row, operation_id, result, attrs) do
    q!(
      repo,
      "UPDATE fount_run_provider_requests SET status=$2,provider_request_id=$3,response=$4::jsonb,response_fingerprint=$5,usage=$6::jsonb,error_category=$7,responded_at=now(),updated_at=now() WHERE id=$1::text::uuid",
      [
        row["id"],
        attrs.status,
        result["id"],
        attrs.response,
        attrs.fingerprint,
        attrs.usage,
        attrs.error_category
      ]
    )

    settle_usage_locked(repo, row["usage_id"], result)
    provider_row(repo, operation_id)
  end

  def reserve_measurement(repo, claim, operation_id, quantity)
      when is_map(claim) and is_binary(operation_id) and is_integer(quantity) and quantity >= 0 do
    tx(repo, fn ->
      run = locked_run(repo, claim["run_id"])
      ensure_claim_owner!(repo, run, claim, :dispatch)

      existing =
        one(
          repo,
          "SELECT * FROM fount_run_usage WHERE operation_id=$1 AND resource='measurement_states' FOR UPDATE",
          [operation_id]
        )

      usage =
        reserve_usage_locked(
          repo,
          run,
          claim,
          operation_id,
          "measurement_states",
          quantity,
          nil,
          nil
        )

      if is_nil(existing) do
        q!(
          repo,
          "UPDATE fount_run_usage SET settled_quantity=reserved_quantity,knowledge_state='known',reconciliation_state='settled',settled_at=now(),updated_at=now() WHERE id=$1::text::uuid",
          [usage["id"]]
        )

        q!(
          repo,
          "UPDATE fount_run_steps SET measurement_state_count=measurement_state_count+$2,updated_at=now() WHERE id=$1::text::uuid",
          [claim["step_id"], quantity]
        )
      end

      quantity
    end)
  end

  def complete(repo, claim, result) when is_map(claim) and is_map(result) do
    if ClosedMap.json?(result) do
      tx(repo, fn -> complete_locked(repo, claim, result) end)
    else
      {:error, :invalid_step_result}
    end
  end

  def partial(repo, claim, reason, details \\ %{}) when is_map(claim) and is_map(details) do
    tx(repo, fn ->
      run = locked_run(repo, claim["run_id"])
      ensure_claim_owner!(repo, run, claim, :commit, allow_control: true)
      step = locked_step(repo, claim["run_id"], claim["step_id"])

      q!(
        repo,
        "UPDATE fount_run_steps SET status='waiting',lease_owner=NULL,lease_token=NULL,lease_expires_at=NULL,heartbeat_at=NULL,updated_at=now() WHERE id=$1::text::uuid",
        [claim["step_id"]]
      )

      q!(
        repo,
        "UPDATE fount_run_attempts SET outcome='unknown',redacted_error=$3::jsonb,ended_at=now() WHERE step_id=$1::text::uuid AND attempt_number=$2 AND outcome='running'",
        [
          claim["step_id"],
          claim["attempt_number"],
          %{"reason" => safe_reason(reason), "details" => details}
        ]
      )

      q!(
        repo,
        "UPDATE fount_runs SET active_step_id=NULL,pause_requested_at=COALESCE(pause_requested_at,now()),status='partial',lock_version=lock_version+1,updated_at=now() WHERE id=$1::text::uuid",
        [claim["run_id"]]
      )

      append_event(repo, run, step, claim, "step_partial", %{"reason" => safe_reason(reason)})
      step_row(repo, claim["step_id"])
    end)
  end

  def fail(repo, claim, reason) when is_map(claim) do
    tx(repo, fn ->
      run = locked_run(repo, claim["run_id"])
      ensure_claim_owner!(repo, run, claim, :commit, allow_control: true)
      step = locked_step(repo, claim["run_id"], claim["step_id"])
      error = %{"reason" => safe_reason(reason)}

      q!(
        repo,
        "UPDATE fount_run_steps SET status='failed',lease_owner=NULL,lease_token=NULL,lease_expires_at=NULL,heartbeat_at=NULL,updated_at=now() WHERE id=$1::text::uuid",
        [claim["step_id"]]
      )

      q!(
        repo,
        "UPDATE fount_run_attempts SET outcome='failed',redacted_error=$3::jsonb,ended_at=now() WHERE step_id=$1::text::uuid AND attempt_number=$2 AND outcome='running'",
        [claim["step_id"], claim["attempt_number"], error]
      )

      q!(
        repo,
        "UPDATE fount_runs SET active_step_id=NULL,status='partial',lock_version=lock_version+1,updated_at=now() WHERE id=$1::text::uuid",
        [claim["run_id"]]
      )

      append_event(repo, run, step, claim, "step_failed", error)
      step_row(repo, claim["step_id"])
    end)
  end

  @doc "Phase-03 test/storage primitive. Public writer steering commands remain Phase 05."
  def install_control_request(repo, run_id, kind, %ActorContext{} = context)
      when kind in [:pause, :stop] do
    tx(repo, fn ->
      run = locked_run(repo, run_id)
      authorize!(repo, run, context, :manage_run)
      column = if kind == :pause, do: "pause_requested_at", else: "stop_requested_at"
      status = if kind == :pause, do: "paused", else: "stopped"

      q!(
        repo,
        "UPDATE fount_runs SET #{column}=COALESCE(#{column},now()),status=$2,current_fencing_token=current_fencing_token+1,lock_version=lock_version+1,updated_at=now() WHERE id=$1::text::uuid",
        [run_id, status]
      )

      :ok
    end)
  end

  def progress(repo, run_id, %ActorContext{} = context) do
    run = one(repo, "SELECT * FROM fount_runs WHERE id=$1::text::uuid", [run_id])

    if is_nil(run) do
      {:error, :not_found}
    else
      with :ok <- authorize(run, context, :read_run) do
        steps =
          rows(
            repo,
            "SELECT * FROM fount_run_steps WHERE run_id=$1::text::uuid ORDER BY inserted_at,id",
            [run_id]
          )

        usage =
          rows(
            repo,
            "SELECT id,operation_id,step_id,resource,reserved_quantity,settled_quantity,currency,reserved_cost_microunits,settled_cost_microunits,knowledge_state,reconciliation_state,provider_request_id,inserted_at,updated_at FROM fount_run_usage WHERE run_id=$1::text::uuid ORDER BY inserted_at,id",
            [run_id]
          )

        providers =
          rows(
            repo,
            "SELECT operation_id,step_id,attempt_number,status,provider_request_id,error_category,malformed_repair,transport_retry,intended_at,dispatched_at,responded_at FROM fount_run_provider_requests WHERE run_id=$1::text::uuid ORDER BY intended_at,id",
            [run_id]
          )

        decisions =
          rows(
            repo,
            "SELECT id,step_id,plan_version,policy_version,checkpoint_key,kind,prompt,options,status,candidate_id,base_revision_id,content_hash,check_set_fingerprint,context_fingerprint,authorized_type,authorized_id,response_fingerprint,respondent_type,respondent_id,resolved_at,inserted_at,updated_at FROM fount_run_decisions WHERE run_id=$1::text::uuid ORDER BY inserted_at,id",
            [run_id]
          )

        approval_attempts =
          rows(
            repo,
            "SELECT id,step_id,decision_id,parent_attempt_id,plan_version,plan_fingerprint,policy_version,policy_fingerprint,candidate_id,base_revision_id,content_hash,check_set_fingerprint,reviewer_type,reviewer_id,approver_type,approver_id,callback_operation_id,fencing_token,review_hash,recommendation,approval_id,approval_hash,outcome,outcome_reason,acceptance_id,finished_at,inserted_at,updated_at FROM fount_run_approval_attempts WHERE run_id=$1::text::uuid ORDER BY inserted_at,id",
            [run_id]
          )

        deliveries =
          rows(
            repo,
            "SELECT id,candidate_id,accepted_revision_id,format,options_fingerprint,delivery_key,output_checksum,output_location,state,error,inserted_at,updated_at FROM fount_run_deliveries WHERE run_id=$1::text::uuid ORDER BY inserted_at,id",
            [run_id]
          )

        resources = resource_summary(repo, run)

        {:ok,
         %{
           "run" => run,
           "steps" => steps,
           "analysis" => AnalysisLineage.progress(steps),
           "resources" => resources,
           "decisions" => decisions,
           "approval_attempts" => approval_attempts,
           "deliveries" => deliveries,
           "usage" => usage,
           "provider_requests" => providers
         }}
      end
    end
  rescue
    _error in Postgrex.Error -> {:error, :storage_error}
  end

  def remaining_limits(repo, claim) when is_map(claim) do
    policy =
      one(
        repo,
        "SELECT policy FROM fount_run_policies WHERE run_id=$1::text::uuid AND version=$2",
        [claim["run_id"], claim["policy_version"]]
      )

    step = step_row(repo, claim["step_id"])
    limits = policy["policy"]["limits"]

    {:ok,
     %{
       max_inference_calls:
         max(
           limits["max_inference_calls"] - consumed_quantity(repo, claim["run_id"], "inference"),
           0
         ),
       max_measurement_states:
         max(
           limits["max_measurement_states"] -
             consumed_quantity(repo, claim["run_id"], "measurement_states"),
           0
         ),
       decode_repairs:
         max(limits["max_malformed_repairs_per_call"] - step["malformed_repair_count"], 0),
       transient_retries: max(limits["max_transient_retries"] - step["transient_retry_count"], 0)
     }}
  rescue
    _error in Postgrex.Error -> {:error, :storage_error}
  end

  def operation_key(claim) when is_map(claim), do: claim["operation_key"]

  # -- claim/reclaim ------------------------------------------------------------

  defp claim_locked(repo, run_id, worker_id, context, lease_ms) do
    run = locked_run(repo, run_id)
    authorize!(repo, run, context, :manage_run)
    step = active_or_next_step(repo, run)

    if is_nil(step) do
      {:blocked, :no_work}
    else
      case Transition.evaluate(run, step, :claim) do
        :continue -> claim_step(repo, run, step, worker_id, context, lease_ms)
        {:halt, :pause_requested} -> {:blocked, :pause_requested}
        {:halt, :stop_requested} -> {:blocked, :stop_requested}
        {:halt, reason} -> fence_invalid_step(repo, run, step, context, reason)
      end
    end
  end

  defp active_or_next_step(repo, run) do
    active =
      if run["active_step_id"],
        do: step_with_clock(repo, run["id"], run["active_step_id"], true),
        else: nil

    if active && active["status"] in @terminal do
      q!(
        repo,
        "UPDATE fount_runs SET active_step_id=NULL,updated_at=now() WHERE id=$1::text::uuid",
        [run["id"]]
      )

      next_queued_step(repo, run["id"])
    else
      active || next_queued_step(repo, run["id"])
    end
  end

  defp next_queued_step(repo, run_id) do
    one(
      repo,
      "SELECT s.*,(s.lease_expires_at IS NOT NULL AND s.lease_expires_at>now()) AS lease_live FROM fount_run_steps s WHERE s.run_id=$1::text::uuid AND s.status IN ('queued','waiting') ORDER BY s.inserted_at,s.id LIMIT 1 FOR UPDATE",
      [run_id]
    )
  end

  defp claim_step(repo, run, step, worker_id, context, lease_ms) do
    cond do
      step["lease_live"] ->
        {:blocked, :busy}

      ambiguous_provider?(repo, step["id"]) ->
        mark_ambiguous(repo, run, step, context)

      true ->
        q!(
          repo,
          "UPDATE fount_run_attempts SET outcome='fenced',ended_at=now() WHERE step_id=$1::text::uuid AND outcome='running'",
          [step["id"]]
        )

        token = run["current_fencing_token"] + 1
        attempt_number = next_attempt_number(repo, step["id"])

        q!(
          repo,
          "UPDATE fount_run_steps SET status='running',lease_owner=$2,lease_token=$3,lease_expires_at=now()+($4::bigint * interval '1 millisecond'),heartbeat_at=now(),updated_at=now() WHERE id=$1::text::uuid",
          [step["id"], worker_id, token, lease_ms]
        )

        q!(
          repo,
          "UPDATE fount_runs SET active_step_id=$2::text::uuid,current_fencing_token=$3,status='running',stage=$4,iteration=$5,lock_version=lock_version+1,updated_at=now() WHERE id=$1::text::uuid",
          [run["id"], step["id"], token, step["stage"], step["iteration"]]
        )

        q!(
          repo,
          "INSERT INTO fount_run_attempts(step_id,run_id,attempt_number,fencing_token,outcome) VALUES($1::text::uuid,$2::text::uuid,$3,$4,'running')",
          [step["id"], run["id"], attempt_number, token]
        )

        current = step_row(repo, step["id"])
        operation_key = execution_key(run, current)
        claim = claim_map(run, current, worker_id, token, attempt_number, lease_ms, operation_key)

        append_event(repo, run, current, claim, "step_claimed", %{
          "worker" => worker_id,
          "fencing_token" => token
        })

        {:claimed, claim}
    end
  end

  defp mark_ambiguous(repo, run, step, context) do
    q!(
      repo,
      "UPDATE fount_run_provider_requests SET status='unknown',updated_at=now() WHERE step_id=$1::text::uuid AND status='dispatched'",
      [step["id"]]
    )

    q!(
      repo,
      "UPDATE fount_run_attempts SET outcome='unknown',redacted_error=$2::jsonb,ended_at=now() WHERE step_id=$1::text::uuid AND outcome='running'",
      [step["id"], %{"reason" => "ambiguous_provider_outcome"}]
    )

    q!(
      repo,
      "UPDATE fount_run_steps SET status='waiting',lease_owner=NULL,lease_token=NULL,lease_expires_at=NULL,heartbeat_at=NULL,updated_at=now() WHERE id=$1::text::uuid",
      [step["id"]]
    )

    q!(
      repo,
      "UPDATE fount_runs SET active_step_id=NULL,status='partial',lock_version=lock_version+1,updated_at=now() WHERE id=$1::text::uuid",
      [run["id"]]
    )

    append_event(repo, run, step, %{"attempt_number" => nil}, "provider_outcome_unknown", %{
      "step_id" => step["id"],
      "actor" => context.principal.id
    })

    {:blocked, :ambiguous_provider_outcome}
  end

  defp fence_invalid_step(repo, run, step, context, reason) do
    q!(
      repo,
      "UPDATE fount_run_steps SET status='fenced',lease_owner=NULL,lease_token=NULL,lease_expires_at=NULL,heartbeat_at=NULL,updated_at=now() WHERE id=$1::text::uuid",
      [step["id"]]
    )

    q!(
      repo,
      "UPDATE fount_run_attempts SET outcome='fenced',redacted_error=$2::jsonb,ended_at=now() WHERE step_id=$1::text::uuid AND outcome='running'",
      [step["id"], %{"reason" => safe_reason(reason)}]
    )

    q!(
      repo,
      "UPDATE fount_runs SET active_step_id=NULL,status='partial',lock_version=lock_version+1,updated_at=now() WHERE id=$1::text::uuid",
      [run["id"]]
    )

    append_event(repo, run, step, %{"attempt_number" => nil}, "step_fenced", %{
      "reason" => safe_reason(reason),
      "actor" => context.principal.id
    })

    {:blocked, reason}
  end

  # -- provider accounting ------------------------------------------------------

  defp provider_intent_locked(repo, claim, attrs) do
    run = locked_run(repo, claim["run_id"])
    ensure_claim_owner!(repo, run, claim, :dispatch)
    operation_id = provider_operation_id(claim, attrs)

    existing =
      one(repo, "SELECT * FROM fount_run_provider_requests WHERE operation_id=$1 FOR UPDATE", [
        operation_id
      ])

    if existing,
      do: existing_provider_intent(repo, existing, operation_id, attrs),
      else: insert_provider_intent(repo, run, claim, attrs, operation_id)
  end

  defp existing_provider_intent(repo, existing, operation_id, attrs) do
    usage = usage_row(repo, existing["usage_id"])

    if usage["reserved_cost_microunits"] != attrs.reserved_cost_microunits or
         usage["currency"] != attrs.currency,
       do: rollback(repo, :provider_intent_conflict)

    case existing["status"] do
      "succeeded" ->
        {:reuse, response_map(existing["response"]), operation_id}

      "intended" ->
        {:intended, operation_id}

      status when status in ["dispatched", "unknown"] ->
        rollback(repo, :ambiguous_provider_outcome)

      "failed" ->
        rollback(repo, :provider_attempt_already_failed)

      _ ->
        rollback(repo, :provider_request_conflict)
    end
  end

  defp insert_provider_intent(repo, run, claim, attrs, operation_id) do
    usage =
      reserve_usage_locked(
        repo,
        run,
        claim,
        operation_id <> ":usage",
        "inference",
        1,
        attrs.reserved_cost_microunits,
        attrs.currency
      )

    q!(
      repo,
      ~S"""
      INSERT INTO fount_run_provider_requests(id,operation_id,run_id,screenplay_id,step_id,attempt_number,fencing_token,usage_id,request_fingerprint,request_mode,dispatch_index,transport_retry,malformed_repair,status)
      VALUES($1::text::uuid,$2,$3::text::uuid,$4::text::uuid,$5::text::uuid,$6,$7,$8::text::uuid,$9,$10,$11,$12,$13,'intended')
      """,
      [
        ID.v4(),
        operation_id,
        claim["run_id"],
        run["screenplay_id"],
        claim["step_id"],
        claim["attempt_number"],
        claim["fencing_token"],
        usage["id"],
        attrs.request_sha256,
        attrs.mode,
        attrs.dispatch_index,
        attrs.transport_retry,
        attrs.malformed_repair
      ]
    )

    {:intended, operation_id}
  end

  defp reserve_usage_locked(repo, run, claim, operation_id, resource, quantity, cost, currency) do
    existing =
      one(
        repo,
        "SELECT * FROM fount_run_usage WHERE operation_id=$1 AND resource=$2 FOR UPDATE",
        [operation_id, resource]
      )

    if existing do
      if existing["run_id"] == run["id"] and existing["step_id"] == claim["step_id"] and
           existing["reserved_quantity"] == quantity,
         do: existing,
         else: rollback(repo, :usage_idempotency_conflict)
    else
      policy =
        one(
          repo,
          "SELECT policy FROM fount_run_policies WHERE run_id=$1::text::uuid AND version=$2",
          [run["id"], claim["policy_version"]]
        )

      limits = policy["policy"]["limits"]
      limit = resource_limit(limits, resource)
      consumed = consumed_quantity(repo, run["id"], resource)
      if consumed + quantity > limit, do: rollback(repo, {:budget_exhausted, resource})

      {knowledge, cost, currency} =
        validate_money_reservation(repo, run["id"], limits["money"], cost, currency)

      id = ID.v4()

      q!(
        repo,
        "INSERT INTO fount_run_usage(id,operation_id,run_id,screenplay_id,step_id,attempt_number,session_id,resource,reserved_quantity,reserved_cost_microunits,currency,knowledge_state,reconciliation_state) VALUES($1::text::uuid,$2,$3::text::uuid,$4::text::uuid,$5::text::uuid,$6,$7::text::uuid,$8,$9,$10,$11,$12,'reserved')",
        [
          id,
          operation_id,
          run["id"],
          run["screenplay_id"],
          claim["step_id"],
          claim["attempt_number"],
          claim["session_id"],
          resource,
          quantity,
          cost,
          currency,
          knowledge
        ]
      )

      usage_row(repo, id)
    end
  end

  defp validate_money_reservation(_repo, _run_id, nil, nil, nil), do: {"unknown", nil, nil}

  defp validate_money_reservation(_repo, _run_id, nil, cost, currency),
    do: {if(is_nil(cost), do: "unknown", else: "estimated"), cost, currency}

  defp validate_money_reservation(repo, run_id, money, cost, currency) do
    if is_nil(cost), do: rollback(repo, :money_estimate_required)
    if currency != money["currency"], do: rollback(repo, :currency_mismatch)
    consumed = consumed_cost(repo, run_id, currency)
    if consumed + cost > money["max_microunits"], do: rollback(repo, {:budget_exhausted, "money"})
    {"estimated", cost, currency}
  end

  defp settle_usage_locked(_repo, nil, _result), do: :ok

  defp settle_usage_locked(repo, usage_id, result) do
    row =
      one(repo, "SELECT * FROM fount_run_usage WHERE id=$1::text::uuid FOR UPDATE", [usage_id])

    if row && is_nil(row["settled_quantity"]) do
      cost = measured_cost(result["usage"], row["currency"])
      settled_cost = if is_nil(cost), do: row["reserved_cost_microunits"], else: cost
      knowledge = if is_nil(cost), do: "unknown", else: "known"

      q!(
        repo,
        "UPDATE fount_run_usage SET settled_quantity=$2,settled_cost_microunits=$3,provider_request_id=$4,knowledge_state=$5,reconciliation_state=$6,settled_at=now(),updated_at=now() WHERE id=$1::text::uuid",
        [usage_id, row["reserved_quantity"], settled_cost, result["id"], knowledge, "settled"]
      )

      enforce_settled_money!(repo, row, cost)
    end

    :ok
  end

  defp measured_cost(usage, currency) when is_map(usage) do
    cost = usage["cost_microunits"]

    if is_integer(cost) and cost >= 0 and is_binary(currency) and
         usage["currency"] == currency,
       do: cost,
       else: nil
  end

  defp measured_cost(_, _), do: nil

  defp enforce_settled_money!(repo, row, cost) do
    policy =
      one(
        repo,
        "SELECT p.policy FROM fount_run_policies p JOIN fount_runs r ON r.id=p.run_id AND r.current_policy_version=p.version WHERE p.run_id=$1::text::uuid",
        [row["run_id"]]
      )

    money = get_in(policy, ["policy", "limits", "money"])

    if money &&
         (is_nil(cost) or
            consumed_cost(repo, row["run_id"], money["currency"]) > money["max_microunits"]) do
      q!(
        repo,
        "UPDATE fount_runs SET pause_requested_at=COALESCE(pause_requested_at,now()),status='partial',current_fencing_token=current_fencing_token+1,lock_version=lock_version+1,updated_at=now() WHERE id=$1::text::uuid",
        [row["run_id"]]
      )
    end
  end

  # -- completion ---------------------------------------------------------------

  defp complete_locked(repo, claim, result) do
    run = locked_run(repo, claim["run_id"])
    ensure_claim_owner!(repo, run, claim, :commit)
    step = locked_step(repo, claim["run_id"], claim["step_id"])
    fingerprint = CanonicalJSON.hash(result)
    candidate_id = result["candidate_id"]
    report_ids = result["report_ids"] || []

    q!(
      repo,
      "UPDATE fount_run_steps SET status='succeeded',result=$2::jsonb,result_fingerprint=$3,output_candidate_id=$4::text::uuid,output_revision_id=$5::text::uuid,output_report_ids=$6::jsonb,lease_owner=NULL,lease_token=NULL,lease_expires_at=NULL,heartbeat_at=NULL,completed_at=now(),updated_at=now() WHERE id=$1::text::uuid",
      [claim["step_id"], result, fingerprint, candidate_id, result["revision_id"], report_ids]
    )

    q!(
      repo,
      "UPDATE fount_run_attempts SET outcome='succeeded',ended_at=now() WHERE step_id=$1::text::uuid AND attempt_number=$2 AND outcome='running'",
      [claim["step_id"], claim["attempt_number"]]
    )

    {run_status, next_stage} = checkpoint_transition!(repo, result)

    q!(
      repo,
      "UPDATE fount_runs SET active_step_id=NULL,status=CASE WHEN $3::text IS NOT NULL THEN $3 WHEN pause_requested_at IS NOT NULL THEN 'paused' WHEN EXISTS(SELECT 1 FROM fount_run_steps WHERE run_id=$1::text::uuid AND status IN ('queued','waiting')) THEN 'queued' ELSE 'running' END,stage=COALESCE($4::text,stage),selected_candidate_id=COALESCE($2::text::uuid,selected_candidate_id),lock_version=lock_version+1,updated_at=now() WHERE id=$1::text::uuid",
      [claim["run_id"], candidate_id, run_status, next_stage]
    )

    append_event(repo, run, step, claim, "step_succeeded", %{
      "result_fingerprint" => fingerprint,
      "candidate_id" => candidate_id
    })

    step_row(repo, claim["step_id"])
  end

  defp checkpoint_transition!(repo, result) do
    status = result["run_status"]
    stage = result["next_stage"]

    if status not in [
         nil,
         "waiting_for_decision",
         "waiting_for_approval",
         "partial",
         "completed_candidate",
         "completed_accepted",
         "completed_nonmutating"
       ] or
         stage not in [
           nil,
           "write",
           "iterate",
           "decide",
           "deliver",
           "semantic_plan",
           "semantic_extract",
           "semantic_reconcile",
           "semantic_validate",
           "semantic_persist"
         ] do
      rollback(repo, :invalid_checkpoint_transition)
    end

    {status, stage}
  end

  # -- validation/helpers -------------------------------------------------------

  defp ensure_claim_owner!(repo, run, claim, phase, opts \\ []) do
    step = step_with_clock(repo, claim["run_id"], claim["step_id"], true)
    allow_control = Keyword.get(opts, :allow_control, false)

    if is_nil(step), do: rollback(repo, :step_not_found)
    ensure_run_claim!(repo, run, claim, phase, allow_control)
    ensure_step_claim!(repo, run, step, claim, phase, allow_control)
  end

  defp ensure_run_claim!(repo, run, claim, phase, allow_control) do
    ensure_run_control!(repo, run, phase, allow_control)

    cond do
      run["current_plan_version"] != claim["plan_version"] ->
        rollback(repo, :plan_invalidated)

      run["current_policy_version"] != claim["policy_version"] ->
        rollback(repo, :policy_invalidated)

      run["current_fencing_token"] != claim["fencing_token"] ->
        rollback(repo, :stale_fencing_token)

      run["active_step_id"] != claim["step_id"] ->
        rollback(repo, :stale_fencing_token)

      true ->
        :ok
    end
  end

  defp ensure_run_control!(repo, run, phase, allow_control) do
    cond do
      not allow_control and not is_nil(run["stop_requested_at"]) ->
        rollback(repo, :stop_requested)

      not allow_control and not is_nil(run["pause_requested_at"]) and phase != :commit ->
        rollback(repo, :pause_requested)

      true ->
        :ok
    end
  end

  defp ensure_step_claim!(repo, run, step, claim, phase, allow_control) do
    cond do
      step["lease_owner"] != claim["lease_owner"] ->
        rollback(repo, :stale_lease_owner)

      step["lease_token"] != claim["fencing_token"] ->
        rollback(repo, :stale_fencing_token)

      not step["lease_live"] ->
        rollback(repo, :lease_expired)

      Transition.evaluate(run, step, phase) != :continue and not allow_control ->
        rollback(repo, :invalid_transition)

      true ->
        :ok
    end
  end

  defp guard_row(nil, _claim, _phase), do: {:error, :not_found}

  defp guard_row(row, claim, phase) do
    run = %{
      "current_plan_version" => row["current_plan_version"],
      "current_policy_version" => row["current_policy_version"],
      "pause_requested_at" => row["pause_requested_at"],
      "stop_requested_at" => row["stop_requested_at"]
    }

    step = %{
      "plan_version" => row["plan_version"],
      "policy_version" => row["policy_version"],
      "status" => row["status"]
    }

    cond do
      row["current_fencing_token"] != claim["fencing_token"] -> {:error, :stale_fencing_token}
      row["active_step_id"] != claim["step_id"] -> {:error, :stale_fencing_token}
      row["lease_owner"] != claim["lease_owner"] -> {:error, :stale_lease_owner}
      row["lease_token"] != claim["fencing_token"] -> {:error, :stale_fencing_token}
      not row["lease_live"] -> {:error, :lease_expired}
      Transition.evaluate(run, step, phase) == :continue -> :ok
      true -> {:error, :invalid_transition}
    end
  end

  defp normalize_dispatch(dispatch) do
    with fingerprint when is_binary(fingerprint) and byte_size(fingerprint) == 64 <-
           dispatch[:request_sha256],
         mode when is_binary(mode) and mode != "" <- dispatch[:mode],
         index when is_integer(index) and index > 0 <- dispatch[:dispatch_index],
         retry when is_integer(retry) and retry >= 0 <- Map.get(dispatch, :transport_retry, 0),
         malformed when is_boolean(malformed) <- Map.get(dispatch, :malformed_repair, false),
         cost <- Map.get(dispatch, :reserved_cost_microunits),
         currency <- Map.get(dispatch, :currency),
         true <- valid_dispatch_cost?(cost, currency) do
      {:ok,
       %{
         request_sha256: fingerprint,
         mode: mode,
         dispatch_index: index,
         transport_retry: retry,
         malformed_repair: malformed,
         reserved_cost_microunits: cost,
         currency: currency
       }}
    else
      _ -> {:error, :invalid_provider_dispatch}
    end
  end

  defp valid_dispatch_cost?(nil, nil), do: true

  defp valid_dispatch_cost?(cost, currency),
    do:
      is_integer(cost) and cost >= 0 and is_binary(currency) and
        Regex.match?(~r/^[A-Z]{3}$/, currency)

  defp provider_operation_id(claim, attrs) do
    CanonicalJSON.hash(%{
      "operation" => claim["operation_key"],
      "request_fingerprint" => attrs.request_sha256,
      "mode" => attrs.mode,
      "dispatch_index" => attrs.dispatch_index,
      "transport_retry" => attrs.transport_retry
    })
  end

  defp execution_key(run, step) do
    "run:" <>
      CanonicalJSON.hash(%{
        "run_id" => run["id"],
        "plan_version" => step["plan_version"],
        "policy_version" => step["policy_version"],
        "stage" => step["stage"],
        "iteration" => step["iteration"],
        "branch_id" => step["branch_id"],
        "input_revision_id" => step["input_revision_id"],
        "input_candidate_id" => step["input_candidate_id"],
        "request_fingerprint" => step["request_fingerprint"]
      })
  end

  defp claim_map(run, step, worker_id, token, attempt_number, lease_ms, operation_key) do
    %{
      "run_id" => run["id"],
      "screenplay_id" => run["screenplay_id"],
      "step_id" => step["id"],
      "stage" => step["stage"],
      "iteration" => step["iteration"],
      "branch_id" => step["branch_id"],
      "request" => step["request"],
      "input_revision_id" => step["input_revision_id"],
      "input_candidate_id" => step["input_candidate_id"],
      "session_id" => step["session_id"],
      "measurement_state_count" => step["measurement_state_count"] || 0,
      "plan_version" => step["plan_version"],
      "policy_version" => step["policy_version"],
      "lease_owner" => worker_id,
      "fencing_token" => token,
      "attempt_number" => attempt_number,
      "lease_ms" => lease_ms,
      "operation_key" => operation_key
    }
  end

  defp resource_limit(limits, "inference"), do: limits["max_inference_calls"]
  defp resource_limit(limits, "measurement_states"), do: limits["max_measurement_states"]
  defp resource_limit(_limits, _resource), do: 0

  defp resource_summary(repo, run) do
    policy =
      one(
        repo,
        "SELECT policy FROM fount_run_policies WHERE run_id=$1::text::uuid AND version=$2",
        [run["id"], run["current_policy_version"]]
      )

    limits = get_in(policy || %{}, ["policy", "limits"]) || %{}

    %{
      "inference" =>
        resource_status(
          limits["max_inference_calls"],
          consumed_quantity(repo, run["id"], "inference")
        ),
      "measurement_states" =>
        resource_status(
          limits["max_measurement_states"],
          consumed_quantity(repo, run["id"], "measurement_states")
        )
    }
  end

  defp resource_status(limit, consumed) when is_integer(limit) and is_integer(consumed) do
    %{
      "limit" => limit,
      "consumed" => consumed,
      "remaining" => max(limit - consumed, 0),
      "exhausted" => consumed >= limit
    }
  end

  defp resource_status(_limit, consumed) do
    %{"limit" => nil, "consumed" => consumed, "remaining" => nil, "exhausted" => false}
  end

  defp consumed_quantity(repo, run_id, resource) do
    row =
      one(
        repo,
        "WITH RECURSIVE lineage AS (SELECT id,parent_run_id FROM fount_runs WHERE id=$1::text::uuid UNION ALL SELECT r.id,r.parent_run_id FROM fount_runs r JOIN lineage l ON r.id=l.parent_run_id) SELECT COALESCE(SUM(CASE WHEN u.reconciliation_state='released' THEN 0 ELSE GREATEST(u.reserved_quantity,COALESCE(u.settled_quantity,0)) END),0)::bigint AS total FROM fount_run_usage u WHERE u.run_id IN (SELECT id FROM lineage) AND u.resource=$2",
        [run_id, resource]
      )

    row["total"] || 0
  end

  defp consumed_cost(repo, run_id, currency) do
    row =
      one(
        repo,
        "WITH RECURSIVE lineage AS (SELECT id,parent_run_id FROM fount_runs WHERE id=$1::text::uuid UNION ALL SELECT r.id,r.parent_run_id FROM fount_runs r JOIN lineage l ON r.id=l.parent_run_id) SELECT COALESCE(SUM(CASE WHEN u.reconciliation_state='released' THEN 0 ELSE GREATEST(COALESCE(u.reserved_cost_microunits,0),COALESCE(u.settled_cost_microunits,0)) END),0)::bigint AS total FROM fount_run_usage u WHERE u.run_id IN (SELECT id FROM lineage) AND u.currency=$2",
        [run_id, currency]
      )

    row["total"] || 0
  end

  defp ambiguous_provider?(repo, step_id) do
    one(
      repo,
      "SELECT 1 AS present FROM fount_run_provider_requests WHERE step_id=$1::text::uuid AND status IN ('dispatched','unknown') LIMIT 1",
      [step_id]
    ) != nil
  end

  defp next_attempt_number(repo, step_id) do
    one(
      repo,
      "SELECT COALESCE(MAX(attempt_number),0)+1 AS next FROM fount_run_attempts WHERE step_id=$1::text::uuid",
      [step_id]
    )["next"]
  end

  defp response_map(nil), do: nil

  defp response_map(response) do
    %{
      id: response["id"],
      text: response["text"],
      object: response["object"],
      model: response["model"],
      finish_reason: response["finish_reason"],
      usage: response["usage"] || %{}
    }
  end

  defp append_event(repo, run, step, claim, type, payload) do
    seq =
      one(
        repo,
        "SELECT COALESCE(MAX(sequence),0)+1 AS sequence FROM fount_run_events WHERE run_id=$1::text::uuid",
        [run["id"]]
      )["sequence"]

    actor_type = run["owner_type"]
    actor_id = run["owner_id"]
    attempt_number = claim["attempt_number"]

    q!(
      repo,
      "INSERT INTO fount_run_events(id,run_id,screenplay_id,sequence,step_id,attempt_number,actor_type,actor_id,plan_version,policy_version,event_type,payload,payload_fingerprint,safe_summary) VALUES($1::text::uuid,$2::text::uuid,$3::text::uuid,$4,$5::text::uuid,$6,$7,$8,$9,$10,$11,$12::jsonb,$13,$14)",
      [
        ID.v4(),
        run["id"],
        run["screenplay_id"],
        seq,
        step["id"],
        attempt_number,
        actor_type,
        actor_id,
        step["plan_version"],
        step["policy_version"],
        type,
        payload,
        CanonicalJSON.hash(payload),
        type
      ]
    )
  end

  defp locked_run(repo, run_id),
    do:
      one(repo, "SELECT * FROM fount_runs WHERE id=$1::text::uuid FOR UPDATE", [run_id]) ||
        rollback(repo, :not_found)

  defp locked_step(repo, run_id, step_id),
    do:
      one(
        repo,
        "SELECT * FROM fount_run_steps WHERE run_id=$1::text::uuid AND id=$2::text::uuid FOR UPDATE",
        [run_id, step_id]
      ) || rollback(repo, :step_not_found)

  defp step_row(repo, step_id),
    do: one(repo, "SELECT * FROM fount_run_steps WHERE id=$1::text::uuid", [step_id])

  defp usage_row(repo, id),
    do: one(repo, "SELECT * FROM fount_run_usage WHERE id=$1::text::uuid", [id])

  defp provider_row(repo, operation_id),
    do:
      one(repo, "SELECT * FROM fount_run_provider_requests WHERE operation_id=$1", [operation_id])

  defp step_with_clock(repo, run_id, step_id, lock?) do
    lock = if lock?, do: " FOR UPDATE", else: ""

    one(
      repo,
      "SELECT s.*,(s.lease_expires_at IS NOT NULL AND s.lease_expires_at>now()) AS lease_live FROM fount_run_steps s WHERE s.run_id=$1::text::uuid AND s.id=$2::text::uuid" <>
        lock,
      [run_id, step_id]
    )
  end

  defp authorize!(repo, run, context, permission) do
    case authorize(run, context, permission) do
      :ok -> :ok
      {:error, reason} -> rollback(repo, reason)
    end
  end

  defp authorize(run, context, permission) do
    with :ok <- ActorContext.authorize(context, permission, run["screenplay_id"]),
         true <-
           {run["owner_type"], run["owner_id"]} ==
             {Atom.to_string(context.owner.type), context.owner.id} do
      :ok
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp tx(repo, fun) do
    case repo.transaction(fun) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _error in Postgrex.Error -> {:error, :storage_error}
  end

  defp unwrap_claim({:ok, {:claimed, claim}}), do: {:ok, claim}
  defp unwrap_claim({:ok, {:blocked, reason}}), do: {:error, reason}
  defp unwrap_claim(other), do: other

  defp unwrap_provider_intent({:ok, {:intended, operation_id}}), do: {:ok, operation_id}

  defp unwrap_provider_intent({:ok, {:reuse, response, operation_id}}),
    do: {:reuse, response, operation_id}

  defp unwrap_provider_intent(other), do: other

  defp bool_int(true), do: 1
  defp bool_int(false), do: 0

  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp safe_reason({tag, detail}) when is_atom(tag),
    do: Atom.to_string(tag) <> ":" <> safe_reason(detail)

  defp safe_reason(reason) when is_binary(reason), do: reason
  defp safe_reason(reason), do: inspect(reason, limit: 10, printable_limit: 500)

  defp rollback(repo, reason), do: repo.rollback(reason)
  defp q!(repo, sql, params), do: SQL.query!(repo, sql, params, log: false)

  defp one(repo, sql, params) do
    result = q!(repo, sql, params)

    case result.rows do
      [row | _] -> row_map(result.columns, row)
      [] -> nil
    end
  end

  defp rows(repo, sql, params) do
    result = q!(repo, sql, params)
    Enum.map(result.rows, &row_map(result.columns, &1))
  end

  defp row_map(columns, row), do: Persistence.row_map(columns, row)
end
