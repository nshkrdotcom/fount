defmodule FountRun.ApprovalBridge do
  @moduledoc "Durable bridge from a saved Run approval attempt into Core canonical acceptance."

  alias Ecto.Adapters.SQL
  alias Fount.ID
  alias Fount.Persistence, as: CorePersistence
  alias Fount.Screenplay.Model
  alias Fount.Writing.{Approval, Authority, Principal, Review}
  alias FountRun.{ActorContext, Persistence}

  @open ~w(pending reviewed ready unknown)

  def accept_ready(repo, attempt_id, %ActorContext{} = context, opts \\ []) do
    result = tx(repo, fn -> accept_ready_locked!(repo, attempt_id, context, opts) end)

    case result do
      {:error, {:core_acceptance_rejected, reason}} ->
        case record_core_failure(repo, attempt_id, context, reason) do
          :ok ->
            {:error, {:core_acceptance_rejected, reason}}

          {:error, history_reason} ->
            {:error, {:core_acceptance_history_failed, reason, history_reason}}
        end

      {:ok, value} ->
        case fault(opts, :after_acceptance_commit) do
          :ok -> {:ok, value}
          {:error, reason} -> {:error, reason}
        end

      other ->
        other
    end
  end

  defp accept_ready_locked!(repo, attempt_id, context, opts) do
    identity =
      one(repo, "SELECT run_id::text FROM fount_run_approval_attempts WHERE id=$1::text::uuid", [
        attempt_id
      ]) ||
        rollback(repo, :not_found)

    run = locked_run!(repo, identity["run_id"], context)

    attempt =
      one(repo, "SELECT * FROM fount_run_approval_attempts WHERE id=$1::text::uuid FOR UPDATE", [
        attempt_id
      ]) ||
        rollback(repo, :not_found)

    authorize_attempt!(repo, run, attempt, context)

    case attempt["outcome"] do
      "accepted" ->
        acceptance =
          acceptance_by_approval(repo, attempt["approval_id"]) ||
            rollback(repo, :acceptance_missing)

        acceptance_result(run, attempt, acceptance, true)

      "ready" ->
        accept_new_ready!(repo, run, attempt, context, opts)

      outcome ->
        rollback(repo, {:approval_not_ready, outcome})
    end
  end

  defp accept_new_ready!(repo, run, attempt, context, opts) do
    validate_fresh_attempt!(repo, run, attempt)
    :ok = fault!(repo, opts, :before_core_acceptance)
    approval = unwrap!(repo, Approval.from_map(attempt["approval_payload"] || %{}))
    authority = unwrap!(repo, Authority.new(context.principal, run["screenplay_id"], [:approve]))

    case CorePersistence.accept_candidate(repo, attempt["candidate_id"],
           approval: approval,
           authority: authority
         ) do
      {:error, reason} ->
        # Core and Run acceptance are atomic; a separate transaction records rejection history.
        rollback(repo, {:core_acceptance_rejected, reason})

      {:ok, _model} ->
        :ok = fault!(repo, opts, :after_core_acceptance_before_commit)
        record_accepted!(repo, run, attempt, context, opts)
    end
  end

  defp record_accepted!(repo, run, attempt, context, opts) do
    acceptance =
      acceptance_by_approval(repo, attempt["approval_id"]) || rollback(repo, :acceptance_missing)

    q!(
      repo,
      "UPDATE fount_run_approval_attempts SET outcome='accepted',outcome_reason=NULL,acceptance_id=$2::text::uuid,finished_at=now(),updated_at=now() WHERE id=$1::text::uuid",
      [attempt["id"], acceptance["id"]]
    )

    unless Keyword.get(opts, :defer_run_completion, false) do
      q!(
        repo,
        "UPDATE fount_runs SET selected_candidate_id=$2::text::uuid,status='partial',stage='deliver',active_step_id=NULL,lock_version=lock_version+1,updated_at=now() WHERE id=$1::text::uuid",
        [run["id"], attempt["candidate_id"]]
      )
    end

    event!(repo, run["id"], context, "candidate_accepted", %{
      "approval_attempt_id" => attempt["id"],
      "approval_id" => attempt["approval_id"],
      "acceptance_id" => acceptance["id"],
      "candidate_id" => attempt["candidate_id"]
    })

    acceptance_result(run, Map.put(attempt, "outcome", "accepted"), acceptance, false)
  end

  defp record_core_failure(repo, attempt_id, context, reason) do
    case tx(repo, fn -> record_core_failure_locked!(repo, attempt_id, context, reason) end) do
      {:ok, :ok} -> :ok
      {:error, history_reason} -> {:error, history_reason}
    end
  end

  defp record_core_failure_locked!(repo, attempt_id, context, reason) do
    identity =
      one(repo, "SELECT run_id::text FROM fount_run_approval_attempts WHERE id=$1::text::uuid", [
        attempt_id
      ]) ||
        rollback(repo, :not_found)

    run = locked_run!(repo, identity["run_id"], context)

    attempt =
      one(repo, "SELECT * FROM fount_run_approval_attempts WHERE id=$1::text::uuid FOR UPDATE", [
        attempt_id
      ]) ||
        rollback(repo, :not_found)

    if attempt["outcome"] == "ready" do
      outcome = if match?({:stale_revision, _}, reason), do: "fenced", else: "failed"

      q!(
        repo,
        "UPDATE fount_run_approval_attempts SET outcome=$2,outcome_reason=$3,finished_at=now(),updated_at=now() WHERE id=$1::text::uuid",
        [attempt_id, outcome, inspect(reason)]
      )

      event!(repo, run["id"], context, "core_acceptance_rejected", %{
        "approval_attempt_id" => attempt_id,
        "reason" => inspect(reason)
      })
    end

    :ok
  end

  @doc "Runs a registered automated reviewer exactly once after persisting callback intent."
  def automated(repo, run, candidate_id, owner_context, approval_context, callback, opts \\ [])

  def automated(
        repo,
        run,
        candidate_id,
        %ActorContext{} = owner_context,
        %ActorContext{} = approval_context,
        callback,
        opts
      )
      when is_function(callback, 1) do
    with :ok <- approval_dispatch_allowed(repo, run["id"]),
         {:ok, packet} <- FountWorkshop.Review.packet(repo, candidate_id),
         {:ok, approver} <- policy_approver(run),
         :ok <- exact_principal(approver, approval_context.principal),
         true <-
           ActorContext.allowed_approver?(owner_context, approval_context.principal) or
             {:error, :unregistered_approver},
         {:ok, attempt} <-
           ensure_automated_attempt(
             repo,
             run,
             packet,
             owner_context,
             approval_context.principal,
             opts
           ) do
      recover_or_dispatch(
        repo,
        run,
        packet,
        attempt,
        owner_context,
        approval_context,
        callback,
        opts
      )
    end
  end

  def automated(_repo, _run, _candidate_id, _owner, _approval, _callback, _opts),
    do: {:error, :invalid_approval_callback}

  defp recover_or_dispatch(
         repo,
         run,
         packet,
         attempt,
         owner_context,
         approval_context,
         callback,
         opts
       ) do
    control_state = current_control_state(repo, run["id"])

    cond do
      attempt["outcome"] == "accepted" ->
        accept_ready(repo, attempt["id"], approval_context, opts)

      attempt["outcome"] in ~w(rejected invalid failed fenced) ->
        {:error, {:approval_attempt_terminal, attempt["outcome"], attempt["outcome_reason"]}}

      control_state == :stopped ->
        {:error, :stopped}

      control_state == :paused ->
        {:partial, :approval_paused, %{"approval_attempt_id" => attempt["id"]}}

      true ->
        recover_saved_or_dispatch(
          repo,
          run,
          packet,
          attempt,
          owner_context,
          approval_context,
          callback,
          opts
        )
    end
  end

  defp recover_saved_or_dispatch(
         repo,
         run,
         packet,
         attempt,
         owner_context,
         approval_context,
         callback,
         opts
       ) do
    cond do
      attempt["outcome"] == "ready" ->
        accept_ready(repo, attempt["id"], approval_context, opts)

      not is_nil(attempt["received_review"]) ->
        continue_saved_review(repo, run, attempt, owner_context, approval_context, opts)

      attempt["outcome"] == "unknown" or attempt["outcome_reason"] == "callback_dispatched" ->
        reconcile_unknown(repo, run, packet, attempt, owner_context, approval_context, opts)

      true ->
        dispatch_callback(
          repo,
          run,
          packet,
          attempt,
          owner_context,
          approval_context,
          callback,
          opts
        )
    end
  end

  defp dispatch_callback(
         repo,
         run,
         packet,
         attempt,
         owner_context,
         approval_context,
         callback,
         opts
       ) do
    with :ok <- fault(opts, :before_callback_dispatch),
         {:ok, marked} <- mark_callback_dispatched(repo, attempt["id"], owner_context),
         {:ok, response} <- invoke_callback(callback, packet),
         :ok <- fault(opts, :after_callback_response_before_persistence) do
      persist_automated_response(
        repo,
        run,
        marked,
        packet,
        response,
        owner_context,
        approval_context,
        opts
      )
    else
      {:error, {:fault, :before_callback_dispatch, _detail} = reason} ->
        {:error, reason}

      {:error, reason} ->
        _ =
          Persistence.record_approval_outcome(
            repo,
            attempt["id"],
            "unknown",
            inspect(reason),
            owner_context
          )

        {:partial, :approval_outcome_unknown, %{"approval_attempt_id" => attempt["id"]}}
    end
  end

  defp persist_automated_response(
         repo,
         run,
         attempt,
         packet,
         response,
         owner_context,
         approval_context,
         opts
       ) do
    evidence = callback_evidence(response)

    with {:ok, _saved_response} <-
           Persistence.record_approval_callback_response(
             repo,
             attempt["id"],
             evidence,
             owner_context
           ),
         {:ok, response} <- normalize_review_response(response),
         {:ok, review} <- review_from_packet(packet, approval_context.principal, response),
         {:ok, saved} <-
           Persistence.record_approval_review(
             repo,
             attempt["id"],
             review,
             response["recommendation"],
             owner_context
           ) do
      review_context = %{
        run: run,
        attempt: attempt,
        saved: saved,
        review: review,
        owner: owner_context,
        approval: approval_context,
        opts: opts
      }

      apply_automated_recommendation(repo, response["recommendation"], review_context)
    else
      {:error, {:fault, _stage, _detail} = reason} ->
        {:error, reason}

      {:error, reason} ->
        _ =
          Persistence.record_approval_outcome(
            repo,
            attempt["id"],
            "invalid",
            inspect(reason),
            owner_context
          )

        {:error, reason}
    end
  end

  defp apply_automated_recommendation(repo, "reject", ctx) do
    Persistence.record_approval_outcome(
      repo,
      ctx.attempt["id"],
      "rejected",
      "reviewer_rejected",
      ctx.owner
    )
  end

  defp apply_automated_recommendation(repo, "approve", ctx) do
    with :ok <- fault(ctx.opts, :after_review_persistence),
         {:ok, ready} <-
           persist_approval(
             repo,
             ctx.run,
             ctx.saved,
             ctx.review,
             ctx.owner,
             ctx.approval.principal
           ),
         :ok <- fault(ctx.opts, :after_approval_payload_persistence) do
      accept_ready(repo, ready["id"], ctx.approval, ctx.opts)
    end
  end

  defp reconcile_unknown(repo, run, packet, attempt, owner_context, approval_context, opts) do
    case Keyword.get(opts, :approval_reconciler) do
      reconciler when is_function(reconciler, 2) ->
        case invoke_reconciler(reconciler, attempt["callback_operation_id"], packet) do
          {:ok, response} ->
            persist_automated_response(
              repo,
              run,
              attempt,
              packet,
              response,
              owner_context,
              approval_context,
              opts
            )

          :unknown ->
            {:partial, :approval_outcome_unknown, %{"approval_attempt_id" => attempt["id"]}}

          {:error, reason} ->
            {:partial, :approval_outcome_unknown,
             %{
               "approval_attempt_id" => attempt["id"],
               "reconciliation_error" => safe_reason(reason)
             }}
        end

      _ ->
        {:partial, :approval_outcome_unknown, %{"approval_attempt_id" => attempt["id"]}}
    end
  end

  defp invoke_reconciler(reconciler, operation_id, packet) do
    case reconciler.(operation_id, packet) do
      {:ok, value} when is_map(value) -> {:ok, value}
      :unknown -> :unknown
      {:error, reason} -> {:error, reason}
      _ -> {:error, :malformed_reconciliation_response}
    end
  rescue
    _error -> {:error, :approval_reconciliation_exception}
  catch
    _kind, _reason -> {:error, :approval_reconciliation_throw}
  end

  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason({reason, _}) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason(_), do: "reconciliation_failed"

  defp continue_saved_review(repo, run, attempt, owner_context, approval_context, opts) do
    case attempt["recommendation"] do
      "reject" ->
        Persistence.record_approval_outcome(
          repo,
          attempt["id"],
          "rejected",
          "reviewer_rejected",
          owner_context
        )

      "approve" ->
        with {:ok, review} <- Review.from_map(attempt["received_review"] || %{}),
             {:ok, ready} <-
               persist_approval(
                 repo,
                 run,
                 attempt,
                 review,
                 owner_context,
                 approval_context.principal
               ) do
          accept_ready(repo, ready["id"], approval_context, opts)
        end

      _ ->
        {:error, :invalid_saved_review}
    end
  end

  defp ensure_automated_attempt(repo, run, packet, owner_context, principal, opts) do
    with {:ok, _current} <- FountRun.get_run(repo, run["id"], owner_context),
         true <-
           ActorContext.owner?(owner_context, owner_context.principal) or
             {:error, :owner_required} do
      do_ensure_automated_attempt(repo, run, packet, owner_context, principal, opts)
    end
  end

  defp do_ensure_automated_attempt(repo, run, packet, owner_context, principal, opts) do
    callback_id =
      "approval:" <>
        run["id"] <>
        ":" <>
        packet["candidate_id"] <>
        ":" <>
        to_string(run["current_plan_version"]) <>
        ":" <> to_string(run["current_policy_version"])

    attrs = %{
      "step_id" => Keyword.get(opts, :step_id),
      "decision_id" => nil,
      "candidate_id" => packet["candidate_id"],
      "base_revision_id" => packet["base_revision_id"],
      "content_hash" => packet["content_hash"],
      "check_set_fingerprint" => packet["check_set_fingerprint"],
      "packet" =>
        packet
        |> Map.put("run_check_set_fingerprint", Keyword.get(opts, :run_check_set_fingerprint))
        |> scrub_packet(),
      "packet_artifact_ref" => nil,
      "reviewer" => Principal.to_map(principal),
      "approver" => Principal.to_map(principal),
      "callback_operation_id" => callback_id,
      "fencing_token" => run["current_fencing_token"]
    }

    case one(repo, "SELECT * FROM fount_run_approval_attempts WHERE callback_operation_id=$1", [
           callback_id
         ]) do
      nil ->
        current =
          one(
            repo,
            "SELECT current_plan_version,current_policy_version,current_fencing_token FROM fount_runs WHERE id=$1::text::uuid",
            [run["id"]]
          )

        if current &&
             {current["current_plan_version"], current["current_policy_version"],
              current["current_fencing_token"]} ==
               {run["current_plan_version"], run["current_policy_version"],
                run["current_fencing_token"]} do
          Persistence.create_approval_attempt(repo, run["id"], attrs, owner_context)
        else
          {:error, :stale_run_snapshot}
        end

      existing ->
        {:ok, existing}
    end
  end

  defp persist_approval(repo, run, attempt, review, context, approver) do
    approval_id = attempt["approval_id"] || ID.v5(attempt["id"], "canonical-approval")

    with {:ok, approval} <-
           Approval.new(
             id: approval_id,
             approver: approver,
             screenplay_id: run["screenplay_id"],
             candidate_id: attempt["candidate_id"],
             base_revision_id: attempt["base_revision_id"],
             content_hash: attempt["content_hash"],
             review: review,
             run_id: run["id"],
             run_policy_version: attempt["policy_version"],
             run_policy_fingerprint: attempt["policy_fingerprint"]
           ) do
      Persistence.record_approval_payload(repo, attempt["id"], approval_id, approval, context)
    end
  end

  defp mark_callback_dispatched(repo, attempt_id, context) do
    tx(repo, fn ->
      identity =
        one(
          repo,
          "SELECT run_id::text FROM fount_run_approval_attempts WHERE id=$1::text::uuid",
          [attempt_id]
        ) || rollback(repo, :not_found)

      run = locked_run!(repo, identity["run_id"], context)
      if run["stop_requested_at"], do: rollback(repo, :stopped)
      if run["pause_requested_at"], do: rollback(repo, :paused)

      row =
        one(
          repo,
          "SELECT * FROM fount_run_approval_attempts WHERE id=$1::text::uuid FOR UPDATE",
          [attempt_id]
        ) || rollback(repo, :not_found)

      if row["outcome"] == "pending" and is_nil(row["outcome_reason"]) do
        q!(
          repo,
          "UPDATE fount_run_approval_attempts SET outcome_reason='callback_dispatched',updated_at=now() WHERE id=$1::text::uuid",
          [attempt_id]
        )

        event!(repo, run["id"], context, "approval_callback_dispatched", %{
          "approval_attempt_id" => attempt_id
        })
      end

      one(repo, "SELECT * FROM fount_run_approval_attempts WHERE id=$1::text::uuid", [attempt_id])
    end)
  end

  defp invoke_callback(callback, packet) do
    case callback.(packet) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
      value when is_map(value) -> {:ok, value}
      _ -> {:error, :malformed_approval_response}
    end
  rescue
    error -> {:error, {:approval_callback_exception, Exception.message(error)}}
  catch
    kind, reason -> {:error, {:approval_callback_throw, kind, inspect(reason)}}
  end

  defp callback_evidence(response) when is_map(response) do
    response = Map.new(response, fn {key, value} -> {to_string(key), value} end)
    allowed = ~w(recommendation findings overrides)
    known = Map.take(response, allowed)
    unknown_fields = Map.keys(response) -- allowed

    safe_known =
      if FountRun.ClosedMap.json?(known),
        do: known,
        else: %{"malformed_known_fields" => true}

    %{"response" => safe_known, "unknown_fields" => Enum.sort(unknown_fields)}
  end

  defp callback_evidence(_response),
    do: %{"response" => %{"malformed_non_object" => true}, "unknown_fields" => []}

  defp normalize_review_response(response) when is_map(response) do
    allowed = ~w(recommendation findings overrides)
    response = Map.new(response, fn {k, v} -> {to_string(k), v} end)

    cond do
      Map.keys(response) -- allowed != [] ->
        {:error, :malformed_approval_response}

      response["recommendation"] not in ["approve", "reject"] ->
        {:error, :malformed_approval_response}

      not is_list(response["findings"] || []) ->
        {:error, :malformed_approval_response}

      not is_list(response["overrides"] || []) ->
        {:error, :malformed_approval_response}

      true ->
        {:ok, Map.merge(%{"findings" => [], "overrides" => []}, response)}
    end
  end

  defp normalize_review_response(_), do: {:error, :malformed_approval_response}

  defp review_from_packet(packet, principal, response) do
    Review.new(
      reviewer: principal,
      candidate_id: packet["candidate_id"],
      base_revision_id: packet["base_revision_id"],
      content_hash: packet["content_hash"],
      report_ids: packet["report_ids"] || [],
      check_set_fingerprint: packet["check_set_fingerprint"],
      findings: response["findings"],
      recommendation: response["recommendation"],
      overrides: response["overrides"]
    )
  end

  defp approval_dispatch_allowed(repo, run_id) do
    case current_control_state(repo, run_id) do
      :running -> :ok
      :paused -> {:error, :paused}
      :stopped -> {:error, :stopped}
      :missing -> {:error, :not_found}
    end
  rescue
    _ in Postgrex.Error -> {:error, :storage_error}
  end

  defp current_control_state(repo, run_id) do
    case one(
           repo,
           "SELECT pause_requested_at,stop_requested_at FROM fount_runs WHERE id=$1::text::uuid",
           [run_id]
         ) do
      nil -> :missing
      %{"stop_requested_at" => value} when not is_nil(value) -> :stopped
      %{"pause_requested_at" => value} when not is_nil(value) -> :paused
      _ -> :running
    end
  end

  defp policy_approver(run) do
    case get_in(run, ["policy", "policy", "approver"]) do
      %{} = value -> Principal.from_map(value)
      _ -> {:error, :approval_policy_missing}
    end
  end

  defp exact_principal(%Principal{} = left, %Principal{} = right) do
    if Principal.to_map(left) == Principal.to_map(right), do: :ok, else: {:error, :wrong_approver}
  end

  defp validate_fresh_attempt!(repo, run, attempt) do
    cond do
      run["stop_requested_at"] ->
        rollback(repo, :stopped)

      run["pause_requested_at"] ->
        rollback(repo, :paused)

      run["current_plan_version"] != attempt["plan_version"] ->
        fence!(repo, attempt, :stale_plan)

      run["current_policy_version"] != attempt["policy_version"] ->
        fence!(repo, attempt, :stale_policy)

      run["current_fencing_token"] != attempt["fencing_token"] ->
        fence!(repo, attempt, :stale_fencing_token)

      true ->
        :ok
    end
  end

  defp authorize_attempt!(repo, run, attempt, context) do
    authorize_run!(repo, run, context)

    expected = {attempt["approver_type"], attempt["approver_id"]}
    actual = {Atom.to_string(context.principal.type), context.principal.id}
    if expected != actual, do: rollback(repo, :wrong_approver)
  end

  defp authorize_run!(repo, run, context) do
    case ActorContext.authorize(context, :manage_run, run["screenplay_id"]) do
      :ok -> :ok
      {:error, reason} -> rollback(repo, reason)
    end

    if {run["owner_type"], run["owner_id"]} !=
         {Atom.to_string(context.owner.type), context.owner.id},
       do: rollback(repo, :unauthorized)
  end

  defp fence!(repo, attempt, reason) do
    if attempt["outcome"] in @open do
      q!(
        repo,
        "UPDATE fount_run_approval_attempts SET outcome='fenced',outcome_reason=$2,finished_at=now(),updated_at=now() WHERE id=$1::text::uuid",
        [attempt["id"], to_string(reason)]
      )
    end

    rollback(repo, reason)
  end

  defp acceptance_by_approval(repo, approval_id) do
    one(
      repo,
      "SELECT id::text,screenplay_id::text,candidate_id::text,result_revision_id::text,approval_id::text FROM acceptances WHERE approval_id=$1::text::uuid",
      [approval_id]
    )
  end

  defp acceptance_result(run, attempt, acceptance, replay) do
    %{
      "run_id" => run["id"],
      "candidate_id" => attempt["candidate_id"],
      "approval_attempt_id" => attempt["id"],
      "approval_id" => attempt["approval_id"],
      "acceptance_id" => acceptance["id"],
      "accepted_revision_id" => acceptance["result_revision_id"],
      "status" => "accepted",
      "delivery_status" => "pending",
      "replay" => replay
    }
  end

  defp scrub_packet(packet),
    do: packet |> Map.drop(["original_fountain", "proposed_fountain"]) |> Model.plain()

  defp event!(repo, run_id, context, type, payload) do
    case Persistence.append_event(repo, run_id, type, payload, context) do
      {:ok, value} -> value
      {:error, reason} -> rollback(repo, reason)
    end
  end

  defp locked_run!(repo, run_id, context) do
    run =
      one(repo, "SELECT * FROM fount_runs WHERE id=$1::text::uuid FOR UPDATE", [run_id]) ||
        rollback(repo, :not_found)

    authorize_run!(repo, run, context)
    run
  end

  defp fault!(repo, opts, stage) do
    case fault(opts, stage) do
      :ok -> :ok
      {:error, reason} -> rollback(repo, reason)
    end
  end

  defp fault(opts, stage) do
    case Keyword.get(opts, :fault_injector) do
      nil ->
        :ok

      fun when is_function(fun, 1) ->
        case fun.(stage) do
          :ok -> :ok
          {:error, reason} -> {:error, {:fault, stage, reason}}
          other -> {:error, {:fault, stage, other}}
        end
    end
  end

  defp one(repo, sql, params) do
    result = SQL.query!(repo, sql, params)

    case result.rows do
      [row | _] -> Persistence.row_map(result.columns, row)
      [] -> nil
    end
  end

  defp q!(repo, sql, params), do: SQL.query!(repo, sql, params)

  defp unwrap!(_repo, {:ok, value}), do: value
  defp unwrap!(repo, {:error, reason}), do: rollback(repo, reason)

  defp tx(repo, fun) do
    case repo.transaction(fun) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ in Postgrex.Error -> {:error, :storage_error}
  end

  defp rollback(repo, reason), do: repo.rollback(reason)
end
