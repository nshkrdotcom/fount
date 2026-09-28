defmodule FountRun.Persistence do
  @moduledoc "Transactional Run storage on a caller-supplied Ecto Repo."

  alias Ecto.Adapters.SQL
  alias Fount.ID
  alias Fount.Writing.CanonicalJSON
  alias FountRun.{ActorContext, ApprovalAttempt, Attempt, Budget, Decision, Delivery, Plan, Policy, Step}

  @run_fields ~w(id owner_type owner_id screenplay_id client_idempotency_key input_fingerprint current_plan_version current_policy_version status stage iteration selected_candidate_id active_step_id current_fencing_token parent_run_id superseding_run_id lock_version pause_requested_at stop_requested_at inserted_at updated_at)a
  @uuid_columns ~w(id screenplay_id selected_candidate_id active_step_id parent_run_id superseding_run_id run_id base_revision_id step_id input_revision_id input_candidate_id session_id output_candidate_id output_revision_id decision_id candidate_id acceptance_id accepted_revision_id result_revision_id revision_id)

  @start_keys ~w(screenplay_id base_revision_id goal scope constraints protected_material input_brief input_notes operation_parameters policy client_idempotency_key)
  @list_keys ~w(status stage limit)

  def start_run(repo, attrs, %ActorContext{} = context, opts \\ []) do
    storage_safe(fn ->
      with :ok <- validate_start_opts(opts),
           {:ok, attrs} <- FountRun.ClosedMap.normalize(attrs, @start_keys),
           :ok <- ActorContext.authorize(context, :manage_run, Map.get(attrs, "screenplay_id")),
           {:ok, key} <- nonempty(attrs, "client_idempotency_key"),
           {:ok, plan} <- Plan.new(Map.drop(attrs, ["policy", "client_idempotency_key"]), context.principal),
           {:ok, policy} <- Policy.new(Map.get(attrs, "policy"), context),
           :ok <- verify_base(repo, plan.screenplay_id, plan.base_revision_id),
           input_fingerprint <- CanonicalJSON.hash(%{"plan" => Plan.to_map(plan), "policy" => policy.value, "principal" => Fount.Writing.Principal.to_map(context.principal)}),
           result <- transaction(repo, fn -> insert_or_replay_run(repo, plan, policy, key, input_fingerprint, context, opts) end) do
        result
      end
    end)
  end

  def get_run(repo, run_id, %ActorContext{} = context) when is_binary(run_id) do
    storage_safe(fn ->
      with true <- FountRun.ClosedMap.uuid_string(run_id),
           run when not is_nil(run) <- run_row(repo, run_id),
           :ok <- authorize_row(context, run) do
        {:ok, hydrate_run(repo, run)}
      else
        false -> {:error, :invalid_run_id}
        nil -> {:error, :not_found}
        {:error, _} = error -> error
      end
    end)
  end

  def list_runs(repo, filter, %ActorContext{} = context) do
    storage_safe(fn ->
      with {:ok, filter} <- FountRun.ClosedMap.normalize(filter || %{}, @list_keys),
           :ok <- ActorContext.authorize(context, :read_run, context.screenplay_id),
           {:ok, limit} <- limit(Map.get(filter, "limit", 50)),
           :ok <- optional_enum(filter, "status", ~w(queued running paused waiting_for_decision waiting_for_approval partial completed_candidate completed_accepted stopped failed)),
           :ok <- optional_enum(filter, "stage", ~w(intake investigate plan write check iterate decide deliver)) do
        conditions = ["screenplay_id=$1::text::uuid", "owner_type=$2", "owner_id=$3"]
        params = [context.screenplay_id, Atom.to_string(context.owner.type), context.owner.id]
        {conditions, params} = maybe_filter(conditions, params, "status", Map.get(filter, "status"))
        {conditions, params} = maybe_filter(conditions, params, "stage", Map.get(filter, "stage"))
        params = params ++ [limit]
        sql = "SELECT #{Enum.join(Enum.map(@run_fields, &Atom.to_string/1), ",")} FROM fount_runs WHERE #{Enum.join(conditions, " AND ")} ORDER BY inserted_at DESC,id LIMIT $#{length(params)}"
        rows = rows(repo, sql, params)
        {:ok, Enum.map(rows, &hydrate_run(repo, &1))}
      end
    end)
  end

  @doc "Appends a same-base/same-scope plan snapshot and atomically advances the pointer."
  def append_plan_snapshot(repo, run_id, attrs, %ActorContext{} = context, opts) do
    transaction(repo, fn ->
      run = locked_run!(repo, run_id, context)
      :ok = or_rollback(repo, require_owner(context))
      expected = Keyword.fetch!(opts, :expected_version)
      if run["current_plan_version"] != expected, do: rollback(repo, {:stale_plan_version, run["current_plan_version"]})
      current = plan_row(repo, run_id, expected)
      attrs = attrs |> Map.delete(:screenplay_id) |> Map.put("screenplay_id", run["screenplay_id"])
      {:ok, plan} = or_rollback(repo, Plan.new(attrs, context.principal))
      if plan.base_revision_id != current["base_revision_id"] or plan.scope != current["scope"], do: rollback(repo, :successor_required)
      :ok = verify_base_or_rollback(repo, plan.screenplay_id, plan.base_revision_id)
      version = expected + 1
      insert_plan(repo, run_id, version, plan, Keyword.get(opts, :reason, "owner_update"))
      q!(repo, "UPDATE fount_runs SET current_plan_version=$2,current_fencing_token=current_fencing_token+1,lock_version=lock_version+1,updated_at=now() WHERE id=$1::text::uuid", [run_id, version])
      append_event_locked(repo, run, version, run["current_policy_version"], context.principal, "plan_snapshot_appended", %{"fingerprint" => plan.fingerprint})
      plan_row(repo, run_id, version)
    end)
  end

  @doc "Appends a policy snapshot under the run lock and advances its pointer."
  def append_policy_snapshot(repo, run_id, value, %ActorContext{} = context, opts) do
    transaction(repo, fn ->
      run = locked_run!(repo, run_id, context)
      :ok = or_rollback(repo, require_owner(context))
      expected = Keyword.fetch!(opts, :expected_version)
      if run["current_policy_version"] != expected, do: rollback(repo, {:stale_policy_version, run["current_policy_version"]})
      {:ok, policy} = or_rollback(repo, Policy.new(value, context))
      version = expected + 1
      insert_policy(repo, run_id, version, policy)
      q!(repo, "UPDATE fount_runs SET current_policy_version=$2,current_fencing_token=current_fencing_token+1,lock_version=lock_version+1,updated_at=now() WHERE id=$1::text::uuid", [run_id, version])
      append_event_locked(repo, run, run["current_plan_version"], version, context.principal, "policy_snapshot_appended", %{"fingerprint" => policy.fingerprint})
      policy_row(repo, run_id, version)
    end)
  end

  @doc "Append-only safe event primitive. Sequence allocation is serialized under the run lock."
  def append_event(repo, run_id, type, payload, %ActorContext{} = context, opts \\ []) do
    with true <- is_binary(type) and String.trim(type) != "",
         true <- is_map(payload) and FountRun.ClosedMap.json?(payload),
         {:ok, binding} <- event_binding(opts) do
      transaction(repo, fn ->
        run = locked_run!(repo, run_id, context)

        append_event_locked(
          repo,
          run,
          Keyword.get(opts, :plan_version, run["current_plan_version"]),
          Keyword.get(opts, :policy_version, run["current_policy_version"]),
          context.principal,
          type,
          payload,
          binding
        )
      end)
    else
      _ -> {:error, :invalid_event}
    end
  end

  @doc "Creates a durable worker-step record without claiming or executing it."
  def create_step(repo, run_id, attrs, %ActorContext{} = context) do
    with {:ok, step} <- Step.validate(attrs) do
      transaction(repo, fn ->
        run = locked_run!(repo, run_id, context)
        id = ID.v4()
        sql = ~S"""
        INSERT INTO fount_run_steps(id,run_id,screenplay_id,plan_version,policy_version,stage,iteration,branch_id,input_revision_id,input_candidate_id,request,request_fingerprint,idempotency_key,status)
        VALUES($1::text::uuid,$2::text::uuid,$3::text::uuid,$4,$5,$6,$7,$8,$9::text::uuid,$10::text::uuid,$11::jsonb,$12,$13,'queued')
        ON CONFLICT(run_id,idempotency_key) DO NOTHING RETURNING id::text
        """
        result = q!(repo, sql, [id, run_id, run["screenplay_id"], run["current_plan_version"], run["current_policy_version"], step.stage, step.iteration, step.branch_id, step.input_revision_id, step.input_candidate_id, step.request, step.request_fingerprint, step.idempotency_key])
        case result.rows do
          [[^id]] -> step_row(repo, id)
          [] ->
            existing = one(repo, "SELECT * FROM fount_run_steps WHERE run_id=$1::text::uuid AND idempotency_key=$2", [run_id, step.idempotency_key])
            if same_step_request?(existing, run, step), do: existing, else: rollback(repo, :idempotency_conflict)
        end
      end)
    end
  end

  @doc "Storage-only active-step/lease write. Claim, renewal, expiry and reclaim policy are Phase 03."
  def store_active_lease(repo, run_id, step_id, lease, %ActorContext{} = context) do
    with {:ok, lease} <- FountRun.ClosedMap.normalize(lease, ~w(owner token expires_at heartbeat_at)),
         true <- FountRun.ClosedMap.nonempty_string(lease["owner"]),
         token when is_integer(token) and token >= 0 <- lease["token"],
         true <- is_binary(lease["expires_at"]) do
      transaction(repo, fn ->
        run = locked_run!(repo, run_id, context)
        if token < run["current_fencing_token"], do: rollback(repo, :stale_fencing_token)
        step = one(repo, "SELECT * FROM fount_run_steps WHERE id=$1::text::uuid AND run_id=$2::text::uuid FOR UPDATE", [step_id, run_id]) || rollback(repo, :not_found)
        q!(repo, "UPDATE fount_run_steps SET lease_owner=$2,lease_token=$3,lease_expires_at=$4::text::timestamptz,heartbeat_at=COALESCE($5::text::timestamptz,now()),updated_at=now() WHERE id=$1::text::uuid", [step_id, lease["owner"], token, lease["expires_at"], lease["heartbeat_at"]])
        q!(repo, "UPDATE fount_runs SET active_step_id=$2::text::uuid,current_fencing_token=GREATEST(current_fencing_token,$3),lock_version=lock_version+1,updated_at=now() WHERE id=$1::text::uuid", [run_id, step_id, token])
        Map.merge(step, %{"lease_owner" => lease["owner"], "lease_token" => token, "lease_expires_at" => lease["expires_at"]})
      end)
    else
      _ -> {:error, :invalid_lease}
    end
  end

  @doc "Begins one durable step attempt. Claiming, dispatch and recovery semantics remain Phase 03."
  def begin_attempt(repo, run_id, attrs, %ActorContext{} = context) do
    with {:ok, attempt} <- Attempt.start(attrs) do
      transaction(repo, fn ->
        run = locked_run!(repo, run_id, context)
        step = one(repo, "SELECT * FROM fount_run_steps WHERE run_id=$1::text::uuid AND id=$2::text::uuid FOR UPDATE", [run_id, attempt.step_id]) || rollback(repo, :step_not_found)

        sql = ~S"""
        INSERT INTO fount_run_attempts(step_id,run_id,attempt_number,fencing_token,outcome)
        VALUES($1::text::uuid,$2::text::uuid,$3,$4,'running')
        ON CONFLICT(step_id,attempt_number) DO NOTHING
        """

        insert = q!(repo, sql, [attempt.step_id, run_id, attempt.attempt_number, attempt.fencing_token])
        row = attempt_row(repo, attempt.step_id, attempt.attempt_number)

        if row["run_id"] == run_id and row["fencing_token"] == attempt.fencing_token do
          if insert.num_rows == 1 do
            append_event_locked(
              repo,
              run,
              step["plan_version"],
              step["policy_version"],
              context.principal,
              "attempt_started",
              %{"attempt_number" => attempt.attempt_number, "fencing_token" => attempt.fencing_token},
              %{step_id: attempt.step_id, attempt_number: attempt.attempt_number}
            )
          end

          row
        else
          rollback(repo, :attempt_conflict)
        end
      end)
    end
  end

  @doc "Finishes one running attempt exactly once; terminal attempt records remain immutable."
  def finish_attempt(repo, step_id, attempt_number, attrs, %ActorContext{} = context) do
    with true <- FountRun.ClosedMap.uuid_string(step_id),
         true <- is_integer(attempt_number) and attempt_number > 0,
         {:ok, result} <- Attempt.finish(attrs) do
      transaction(repo, fn ->
        row = one(repo, "SELECT a.*,s.screenplay_id,s.plan_version,s.policy_version FROM fount_run_attempts a JOIN fount_run_steps s ON s.id=a.step_id AND s.run_id=a.run_id WHERE a.step_id=$1::text::uuid AND a.attempt_number=$2 FOR UPDATE", [step_id, attempt_number]) || rollback(repo, :not_found)
        run = locked_run!(repo, row["run_id"], context)

        cond do
          row["outcome"] == "running" ->
            q!(repo, "UPDATE fount_run_attempts SET outcome=$3,redacted_error=$4::jsonb,provider_request_id=$5,ended_at=now() WHERE step_id=$1::text::uuid AND attempt_number=$2 AND outcome='running'", [step_id, attempt_number, result.outcome, result.redacted_error, result.provider_request_id])
            final = attempt_row(repo, step_id, attempt_number)

            append_event_locked(
              repo,
              run,
              row["plan_version"],
              row["policy_version"],
              context.principal,
              "attempt_finished",
              %{"attempt_number" => attempt_number, "outcome" => result.outcome},
              %{step_id: step_id, attempt_number: attempt_number}
            )

            final

          same_attempt_result?(row, result) ->
            row

          true ->
            rollback(repo, :attempt_already_finished)
        end
      end)
    else
      _ -> {:error, :invalid_attempt_result}
    end
  end

  @doc "Persists an exact pending decision checkpoint; repeated identical checkpoints replay."
  def put_pending_decision(repo, run_id, attrs, %ActorContext{} = context) do
    with {:ok, decision} <- Decision.new(attrs, context.owner),
         true <- ActorContext.allowed_approver?(context, decision.authorized_principal) do
      transaction(repo, fn ->
        run = locked_run!(repo, run_id, context)
        id = ID.v4()
        sql = ~S"""
        INSERT INTO fount_run_decisions(id,run_id,screenplay_id,step_id,plan_version,policy_version,checkpoint_key,kind,prompt,options,candidate_id,base_revision_id,content_hash,check_set_fingerprint,context_fingerprint,status,authorized_type,authorized_id)
        VALUES($1::text::uuid,$2::text::uuid,$3::text::uuid,$4::text::uuid,$5,$6,$7,$8,$9,$10::jsonb,$11::text::uuid,$12::text::uuid,$13,$14,$15,'pending',$16,$17)
        ON CONFLICT(run_id,checkpoint_key) DO NOTHING RETURNING id::text
        """
        result = q!(repo, sql, [id, run_id, run["screenplay_id"], decision.step_id, run["current_plan_version"], run["current_policy_version"], decision.checkpoint_key, decision.kind, decision.prompt, decision.options, decision.candidate_id, decision.base_revision_id, decision.content_hash, decision.check_set_fingerprint, decision.fingerprint, Atom.to_string(decision.authorized_principal.type), decision.authorized_principal.id])
        row = if result.rows == [[id]], do: decision_row(repo, id), else: one(repo, "SELECT * FROM fount_run_decisions WHERE run_id=$1::text::uuid AND checkpoint_key=$2", [run_id, decision.checkpoint_key])
        if row["context_fingerprint"] == decision.fingerprint, do: row, else: rollback(repo, :checkpoint_conflict)
      end)
    else
      false -> {:error, :unauthorized}
      {:error, _} = error -> error
    end
  end

  @doc "Atomically resolves one pending decision; exact response replay is idempotent."
  def resolve_decision(repo, decision_id, response, %ActorContext{} = context) do
    if not FountRun.ClosedMap.json?(response) do
      {:error, :invalid_decision_response}
    else
      transaction(repo, fn ->
      row = one(repo, "SELECT d.*,r.owner_type,r.owner_id FROM fount_run_decisions d JOIN fount_runs r ON r.id=d.run_id WHERE d.id=$1::text::uuid FOR UPDATE", [decision_id]) || rollback(repo, :not_found)
      :ok = or_rollback(repo, ActorContext.authorize(context, :manage_run, row["screenplay_id"]))
      if {row["owner_type"], row["owner_id"]} != {Atom.to_string(context.owner.type), context.owner.id}, do: rollback(repo, :unauthorized)
      if {row["authorized_type"], row["authorized_id"]} != {Atom.to_string(context.principal.type), context.principal.id}, do: rollback(repo, :unauthorized)
      fingerprint = CanonicalJSON.hash(response)
      cond do
        row["status"] == "pending" ->
          q!(repo, "UPDATE fount_run_decisions SET status='resolved',response=$2::jsonb,response_fingerprint=$3,respondent_type=$4,respondent_id=$5,resolved_at=now(),updated_at=now() WHERE id=$1::text::uuid AND status='pending'", [decision_id, response, fingerprint, Atom.to_string(context.principal.type), context.principal.id])
          decision_row(repo, decision_id)
        row["status"] == "resolved" and row["response_fingerprint"] == fingerprint and row["respondent_type"] == Atom.to_string(context.principal.type) and row["respondent_id"] == context.principal.id -> row
        true -> rollback(repo, :already_resolved)
      end
      end)
    end
  end

  @doc "Creates the durable identity for a human/agent/service approval attempt. No callback or Core acceptance runs here."
  def create_approval_attempt(repo, run_id, attrs, %ActorContext{} = context) do
    with {:ok, attempt} <- ApprovalAttempt.validate(attrs),
         true <- ActorContext.allowed_approver?(context, attempt.reviewer),
         true <- ActorContext.allowed_approver?(context, attempt.approver) do
      transaction(repo, fn ->
        run = locked_run!(repo, run_id, context)
        plan = plan_row(repo, run_id, run["current_plan_version"])
        policy = policy_row(repo, run_id, run["current_policy_version"])
        validate_candidate_binding!(repo, run, attempt)
        validate_decision_binding!(repo, run, attempt)
        validate_policy_approver!(repo, policy, attempt)
        {packet, packet_ref} = case attempt.packet do {:inline, v} -> {v, nil}; {:artifact, v} -> {nil, v} end
        id = ID.v4()
        sql = ~S"""
        INSERT INTO fount_run_approval_attempts(id,run_id,screenplay_id,step_id,decision_id,plan_version,plan_fingerprint,policy_version,policy_fingerprint,candidate_id,base_revision_id,content_hash,check_set_fingerprint,packet,packet_artifact_ref,reviewer_type,reviewer_id,approver_type,approver_id,callback_operation_id,fencing_token,outcome)
        VALUES($1::text::uuid,$2::text::uuid,$3::text::uuid,$4::text::uuid,$5::text::uuid,$6,$7,$8,$9,$10::text::uuid,$11::text::uuid,$12,$13,$14::jsonb,$15,$16,$17,$18,$19,$20,$21,'pending')
        ON CONFLICT(callback_operation_id) DO NOTHING RETURNING id::text
        """
        result = q!(repo, sql, [id, run_id, run["screenplay_id"], attempt.step_id, attempt.decision_id, run["current_plan_version"], plan["fingerprint"], run["current_policy_version"], policy["fingerprint"], attempt.candidate_id, attempt.base_revision_id, attempt.content_hash, attempt.check_set_fingerprint, packet, packet_ref, Atom.to_string(attempt.reviewer.type), attempt.reviewer.id, Atom.to_string(attempt.approver.type), attempt.approver.id, attempt.callback_operation_id, attempt.fencing_token])
        row = if result.rows == [[id]], do: approval_attempt_row(repo, id), else: one(repo, "SELECT * FROM fount_run_approval_attempts WHERE callback_operation_id=$1", [attempt.callback_operation_id])
        if same_approval_attempt?(row, run, plan, policy, attempt, packet, packet_ref), do: row, else: rollback(repo, :idempotency_conflict)
      end)
    else
      false -> {:error, :unauthorized}
      {:error, _} = error -> error
    end
  end

  def record_approval_review(repo, attempt_id, review, recommendation, %ActorContext{} = context) do
    with {:ok, payload} <- ApprovalAttempt.review_payload(review),
         true <- is_binary(recommendation) and String.trim(recommendation) != "" do
      hash = ApprovalAttempt.hash_payload(payload)
      transaction(repo, fn ->
        row = locked_approval_attempt!(repo, attempt_id, context)
        validate_review_binding!(repo, row, payload, recommendation)
        cond do
          is_nil(row["received_review"]) ->
            q!(repo, "UPDATE fount_run_approval_attempts SET received_review=$2::jsonb,review_hash=$3,recommendation=$4,outcome='reviewed',updated_at=now() WHERE id=$1::text::uuid", [attempt_id, payload, hash, recommendation])
            approval_attempt_row(repo, attempt_id)
          row["review_hash"] == hash and row["recommendation"] == recommendation -> row
          true -> rollback(repo, :immutable_review_conflict)
        end
      end)
    else
      false -> {:error, :invalid_recommendation}
      {:error, _} = error -> error
    end
  end

  def record_approval_payload(repo, attempt_id, approval_id, approval, %ActorContext{} = context) do
    with true <- is_binary(approval_id) and String.trim(approval_id) != "",
         {:ok, payload} <- ApprovalAttempt.approval_payload(approval) do
      hash = ApprovalAttempt.hash_payload(payload)
      transaction(repo, fn ->
        row = locked_approval_attempt!(repo, attempt_id, context)
        if is_nil(row["received_review"]), do: rollback(repo, :review_required)
        validate_approval_binding!(repo, row, approval_id, payload)
        cond do
          is_nil(row["approval_id"]) ->
            q!(repo, "UPDATE fount_run_approval_attempts SET approval_id=$2,approval_payload=$3::jsonb,approval_hash=$4,outcome='ready',updated_at=now() WHERE id=$1::text::uuid", [attempt_id, approval_id, payload, hash])
            approval_attempt_row(repo, attempt_id)
          row["approval_id"] == approval_id and row["approval_hash"] == hash -> row
          true -> rollback(repo, :immutable_approval_conflict)
        end
      end)
    else
      false -> {:error, :invalid_approval_id}
      {:error, _} = error -> error
    end
  end

  @doc "Records nonaccepted reconciliation outcomes only; canon acceptance is deliberately Phase 05."
  def record_approval_outcome(repo, attempt_id, outcome, reason, %ActorContext{} = context) when outcome in ~w(rejected invalid fenced failed unknown) do
    transaction(repo, fn ->
      row = locked_approval_attempt!(repo, attempt_id, context)

      cond do
        row["outcome"] == outcome and row["outcome_reason"] == reason ->
          row

        row["outcome"] in ~w(accepted rejected invalid fenced failed) ->
          rollback(repo, :already_resolved)

        outcome == "unknown" ->
          q!(repo, "UPDATE fount_run_approval_attempts SET outcome=$2,outcome_reason=$3,finished_at=NULL,updated_at=now() WHERE id=$1::text::uuid", [attempt_id, outcome, reason])
          approval_attempt_row(repo, attempt_id)

        true ->
          q!(repo, "UPDATE fount_run_approval_attempts SET outcome=$2,outcome_reason=$3,finished_at=now(),updated_at=now() WHERE id=$1::text::uuid", [attempt_id, outcome, reason])
          approval_attempt_row(repo, attempt_id)
      end
    end)
  end
  def record_approval_outcome(_repo, _attempt_id, "accepted", _reason, _context), do: {:error, :acceptance_bridge_required}
  def record_approval_outcome(_repo, _attempt_id, _outcome, _reason, _context), do: {:error, :invalid_approval_outcome}

  def reserve_usage(repo, run_id, attrs, %ActorContext{} = context) do
    with {:ok, usage} <- Budget.reservation(attrs) do
      transaction(repo, fn ->
        run = locked_run!(repo, run_id, context)
        id = ID.v4()
        sql = ~S"""
        INSERT INTO fount_run_usage(id,operation_id,run_id,screenplay_id,step_id,attempt_number,session_id,resource,reserved_quantity,reserved_cost_microunits,currency,knowledge_state,reconciliation_state)
        VALUES($1::text::uuid,$2,$3::text::uuid,$4::text::uuid,$5::text::uuid,$6,$7::text::uuid,$8,$9,$10,$11,$12,'reserved')
        ON CONFLICT(operation_id,resource) DO NOTHING RETURNING id::text
        """
        result = q!(repo, sql, [id, usage.operation_id, run_id, run["screenplay_id"], usage.step_id, usage.attempt_number, usage.session_id, usage.resource, usage.reserved_quantity, usage.reserved_cost_microunits, usage.currency, usage.knowledge_state])
        row = if result.rows == [[id]], do: usage_row(repo, id), else: one(repo, "SELECT * FROM fount_run_usage WHERE operation_id=$1 AND resource=$2", [usage.operation_id, usage.resource])
        if same_usage_reservation?(row, run_id, usage), do: row, else: rollback(repo, :idempotency_conflict)
      end)
    end
  end

  def settle_usage(repo, usage_id, attrs, %ActorContext{} = context) do
    with {:ok, settlement} <- Budget.settlement(attrs) do
      transaction(repo, fn ->
        row = one(repo, "SELECT u.*,r.owner_type,r.owner_id FROM fount_run_usage u JOIN fount_runs r ON r.id=u.run_id WHERE u.id=$1::text::uuid FOR UPDATE", [usage_id]) || rollback(repo, :not_found)
        :ok = or_rollback(repo, ActorContext.authorize(context, :manage_run, row["screenplay_id"]))
        if {row["owner_type"], row["owner_id"]} != {Atom.to_string(context.owner.type), context.owner.id}, do: rollback(repo, :unauthorized)
        cond do
          is_nil(row["settled_quantity"]) ->
            q!(repo, "UPDATE fount_run_usage SET settled_quantity=$2,settled_cost_microunits=$3,provider_request_id=$4,knowledge_state=$5,reconciliation_state=$6,settled_at=now(),updated_at=now() WHERE id=$1::text::uuid", [usage_id, settlement.settled_quantity, settlement.settled_cost_microunits, settlement.provider_request_id, settlement.knowledge_state, settlement.reconciliation_state])
            usage_row(repo, usage_id)
          row["settled_quantity"] == settlement.settled_quantity and
              row["settled_cost_microunits"] == settlement.settled_cost_microunits and
              row["provider_request_id"] == settlement.provider_request_id and
              row["knowledge_state"] == settlement.knowledge_state and
              row["reconciliation_state"] == settlement.reconciliation_state ->
            row
          true -> rollback(repo, :already_settled)
        end
      end)
    end
  end

  def create_delivery(repo, run_id, attrs, %ActorContext{} = context) do
    with {:ok, delivery} <- Delivery.validate(attrs) do
      transaction(repo, fn ->
        run = locked_run!(repo, run_id, context)
        id = ID.v4()
        delivery_key = CanonicalJSON.hash(%{"run_id" => run_id, "identity" => delivery.delivery_key})
        sql = ~S"""
        INSERT INTO fount_run_deliveries(id,run_id,screenplay_id,candidate_id,accepted_revision_id,format,options,options_fingerprint,delivery_key,state)
        VALUES($1::text::uuid,$2::text::uuid,$3::text::uuid,$4::text::uuid,$5::text::uuid,$6,$7::jsonb,$8,$9,'pending')
        ON CONFLICT(delivery_key) DO NOTHING RETURNING id::text
        """
        result = q!(repo, sql, [id, run_id, run["screenplay_id"], delivery.candidate_id, delivery.accepted_revision_id, delivery.format, delivery.options, delivery.options_fingerprint, delivery_key])
        if result.rows == [[id]], do: delivery_row(repo, id), else: one(repo, "SELECT * FROM fount_run_deliveries WHERE delivery_key=$1", [delivery_key])
      end)
    end
  end

  def record_delivery_result(repo, delivery_id, result, %ActorContext{} = context) do
    with {:ok, result} <- FountRun.ClosedMap.normalize(result, ~w(state output_checksum output_location error)),
         state when state in ~w(ready failed) <- result["state"],
         :ok <- validate_delivery_result(state, result) do
      transaction(repo, fn ->
        row = one(repo, "SELECT d.*,r.owner_type,r.owner_id FROM fount_run_deliveries d JOIN fount_runs r ON r.id=d.run_id WHERE d.id=$1::text::uuid FOR UPDATE", [delivery_id]) || rollback(repo, :not_found)
        :ok = or_rollback(repo, ActorContext.authorize(context, :manage_run, row["screenplay_id"]))
        if {row["owner_type"], row["owner_id"]} != {Atom.to_string(context.owner.type), context.owner.id}, do: rollback(repo, :unauthorized)
        if row["state"] != "pending", do: rollback(repo, :already_resolved)
        q!(repo, "UPDATE fount_run_deliveries SET state=$2,output_checksum=$3,output_location=$4,error=$5,updated_at=now() WHERE id=$1::text::uuid", [delivery_id, state, result["output_checksum"], result["output_location"], result["error"]])
        delivery_row(repo, delivery_id)
      end)
    else
      _ -> {:error, :invalid_delivery_result}
    end
  end

  defp validate_candidate_binding!(repo, run, attempt) do
    candidate =
      one(
        repo,
        "SELECT c.base_revision_id::text,r.content_hash,c.check_set_fingerprint FROM writing_candidates c JOIN revisions r ON r.screenplay_id=c.screenplay_id AND r.id=c.result_revision_id WHERE c.screenplay_id=$1::text::uuid AND c.id=$2::text::uuid",
        [run["screenplay_id"], attempt.candidate_id]
      ) || rollback(repo, :candidate_not_found)

    expected = {candidate["base_revision_id"], candidate["content_hash"], candidate["check_set_fingerprint"]}
    actual = {attempt.base_revision_id, attempt.content_hash, attempt.check_set_fingerprint}
    if expected != actual, do: rollback(repo, :candidate_binding_mismatch)
  end

  defp validate_decision_binding!(_repo, _run, %{decision_id: nil}), do: :ok

  defp validate_decision_binding!(repo, run, attempt) do
    decision =
      one(
        repo,
        "SELECT status,authorized_type,authorized_id FROM fount_run_decisions WHERE run_id=$1::text::uuid AND id=$2::text::uuid",
        [run["id"], attempt.decision_id]
      ) || rollback(repo, :decision_not_found)

    if decision["status"] != "resolved", do: rollback(repo, :decision_not_resolved)

    if {decision["authorized_type"], decision["authorized_id"]} !=
         {Atom.to_string(attempt.approver.type), attempt.approver.id},
       do: rollback(repo, :decision_approver_mismatch)
  end

  defp validate_policy_approver!(repo, policy, attempt) do
    configured = policy["policy"]["approver"]

    cond do
      is_nil(configured) ->
        rollback(repo, :policy_does_not_accept)

      {configured["type"], configured["id"]} !=
          {Atom.to_string(attempt.approver.type), attempt.approver.id} ->
        rollback(repo, :policy_approver_mismatch)

      true ->
        :ok
    end
  end

  defp validate_review_binding!(repo, row, payload, recommendation) do
    reviewer = payload["reviewer"] || %{}

    expected =
      {row["candidate_id"], row["base_revision_id"], row["content_hash"],
       row["check_set_fingerprint"], row["reviewer_type"], row["reviewer_id"]}

    actual =
      {payload["candidate_id"], payload["base_revision_id"], payload["content_hash"],
       payload["check_set_fingerprint"], reviewer["type"], reviewer["id"]}

    cond do
      expected != actual -> rollback(repo, :review_binding_mismatch)
      payload["recommendation"] != recommendation -> rollback(repo, :recommendation_mismatch)
      true -> :ok
    end
  end

  defp validate_approval_binding!(repo, row, approval_id, payload) do
    approver = payload["approver"] || %{}
    review = payload["review"] || %{}
    review_hash = CanonicalJSON.hash(review)

    expected =
      {approval_id, row["screenplay_id"], row["candidate_id"], row["base_revision_id"], row["content_hash"],
       row["approver_type"], row["approver_id"], row["run_id"], row["policy_version"],
       row["policy_fingerprint"], row["review_hash"]}

    actual =
      {payload["approval_id"], payload["screenplay_id"], payload["candidate_id"], payload["base_revision_id"],
       payload["content_hash"], approver["type"], approver["id"], payload["run_id"],
       payload["run_policy_version"], payload["run_policy_fingerprint"], review_hash}

    if expected != actual, do: rollback(repo, :approval_binding_mismatch)
  end


  defp same_step_request?(existing, run, step) do
    not is_nil(existing) and
      existing["screenplay_id"] == run["screenplay_id"] and
      existing["plan_version"] == run["current_plan_version"] and
      existing["policy_version"] == run["current_policy_version"] and
      existing["stage"] == step.stage and
      existing["iteration"] == step.iteration and
      existing["branch_id"] == step.branch_id and
      existing["input_revision_id"] == step.input_revision_id and
      existing["input_candidate_id"] == step.input_candidate_id and
      existing["request_fingerprint"] == step.request_fingerprint
  end

  defp same_approval_attempt?(row, run, plan, policy, attempt, packet, packet_ref) do
    not is_nil(row) and
      row["run_id"] == run["id"] and
      row["screenplay_id"] == run["screenplay_id"] and
      row["step_id"] == attempt.step_id and
      row["decision_id"] == attempt.decision_id and
      row["plan_version"] == run["current_plan_version"] and
      row["plan_fingerprint"] == plan["fingerprint"] and
      row["policy_version"] == run["current_policy_version"] and
      row["policy_fingerprint"] == policy["fingerprint"] and
      row["candidate_id"] == attempt.candidate_id and
      row["base_revision_id"] == attempt.base_revision_id and
      row["content_hash"] == attempt.content_hash and
      row["check_set_fingerprint"] == attempt.check_set_fingerprint and
      row["packet"] == packet and
      row["packet_artifact_ref"] == packet_ref and
      {row["reviewer_type"], row["reviewer_id"]} == {Atom.to_string(attempt.reviewer.type), attempt.reviewer.id} and
      {row["approver_type"], row["approver_id"]} == {Atom.to_string(attempt.approver.type), attempt.approver.id} and
      row["fencing_token"] == attempt.fencing_token
  end

  defp same_usage_reservation?(row, run_id, usage) do
    not is_nil(row) and
      row["run_id"] == run_id and
      row["step_id"] == usage.step_id and
      row["attempt_number"] == usage.attempt_number and
      row["session_id"] == usage.session_id and
      row["reserved_quantity"] == usage.reserved_quantity and
      row["reserved_cost_microunits"] == usage.reserved_cost_microunits and
      row["currency"] == usage.currency and
      row["knowledge_state"] == usage.knowledge_state
  end

  defp validate_delivery_result("ready", result) do
    if FountRun.ClosedMap.nonempty_string(result["output_checksum"]) and
         FountRun.ClosedMap.nonempty_string(result["output_location"]) and is_nil(result["error"]),
      do: :ok,
      else: {:error, :invalid_delivery_result}
  end

  defp validate_delivery_result("failed", result) do
    if FountRun.ClosedMap.nonempty_string(result["error"]) and is_nil(result["output_checksum"]) and
         is_nil(result["output_location"]),
      do: :ok,
      else: {:error, :invalid_delivery_result}
  end

  defp event_binding(opts) when is_list(opts) do
    step_id = Keyword.get(opts, :step_id)
    attempt_number = Keyword.get(opts, :attempt_number)

    cond do
      not is_nil(step_id) and not FountRun.ClosedMap.uuid_string(step_id) -> {:error, :invalid_step_id}
      not is_nil(attempt_number) and (is_nil(step_id) or not is_integer(attempt_number) or attempt_number <= 0) -> {:error, :invalid_attempt_number}
      true -> {:ok, %{step_id: step_id, attempt_number: attempt_number}}
    end
  end
  defp event_binding(_), do: {:error, :invalid_event_options}

  defp same_attempt_result?(row, result) do
    row["outcome"] == result.outcome and row["redacted_error"] == result.redacted_error and
      row["provider_request_id"] == result.provider_request_id and not is_nil(row["ended_at"])
  end

  defp require_owner(%ActorContext{} = context) do
    if ActorContext.owner?(context, context.principal), do: :ok, else: {:error, :owner_required}
  end

  # -- internal creation/hydration ------------------------------------------------
  defp insert_or_replay_run(repo, plan, policy, key, input_fp, context, _opts) do
    id = ID.v4()
    sql = ~S"""
    INSERT INTO fount_runs(id,owner_type,owner_id,screenplay_id,client_idempotency_key,input_fingerprint,current_plan_version,current_policy_version,status,stage,iteration,current_fencing_token,lock_version)
    VALUES($1::text::uuid,$2,$3,$4::text::uuid,$5,$6,1,1,'queued','intake',0,0,1)
    ON CONFLICT(owner_type,owner_id,client_idempotency_key) DO NOTHING RETURNING id::text
    """
    result = q!(repo, sql, [id, Atom.to_string(context.owner.type), context.owner.id, plan.screenplay_id, key, input_fp])

    case result.rows do
      [[^id]] ->
        insert_plan(repo, id, 1, plan, "run_start")
        insert_policy(repo, id, 1, policy)
        run = run_row(repo, id)
        append_event_locked(repo, run, 1, 1, context.principal, "run_started", %{"input_fingerprint" => input_fp})
        hydrate_run(repo, run)
      [] ->
        existing = one(repo, "SELECT * FROM fount_runs WHERE owner_type=$1 AND owner_id=$2 AND client_idempotency_key=$3 FOR UPDATE", [Atom.to_string(context.owner.type), context.owner.id, key])
        if existing["input_fingerprint"] == input_fp and existing["screenplay_id"] == plan.screenplay_id,
          do: hydrate_run(repo, existing),
          else: rollback(repo, :idempotency_conflict)
    end
  end

  defp insert_plan(repo, run_id, version, plan, reason) do
    q!(repo, ~S"""
    INSERT INTO fount_run_plans(run_id,version,screenplay_id,base_revision_id,goal,scope,constraints,protected_material,input_brief,input_notes,operation_parameters,fingerprint,author_type,author_id,change_reason)
    VALUES($1::text::uuid,$2,$3::text::uuid,$4::text::uuid,$5,$6::jsonb,$7::jsonb,$8::jsonb,$9::jsonb,$10::jsonb,$11::jsonb,$12,$13,$14,$15)
    """, [run_id, version, plan.screenplay_id, plan.base_revision_id, plan.goal, plan.scope, plan.constraints, plan.protected_material, plan.input_brief, plan.input_notes, plan.operation_parameters, plan.fingerprint, Atom.to_string(plan.author.type), plan.author.id, reason])
  end

  defp insert_policy(repo, run_id, version, policy) do
    q!(repo, "INSERT INTO fount_run_policies(run_id,version,policy,fingerprint,author_type,author_id) VALUES($1::text::uuid,$2,$3::jsonb,$4,$5,$6)", [run_id, version, policy.value, policy.fingerprint, Atom.to_string(policy.author.type), policy.author.id])
  end

  defp hydrate_run(repo, run) do
    Map.put(run, "plan", plan_row(repo, run["id"], run["current_plan_version"]))
    |> Map.put("policy", policy_row(repo, run["id"], run["current_policy_version"]))
  end

  defp locked_run!(repo, run_id, context) do
    run = one(repo, "SELECT * FROM fount_runs WHERE id=$1::text::uuid FOR UPDATE", [run_id]) || rollback(repo, :not_found)
    :ok = or_rollback(repo, authorize_row(context, run, :manage_run))
    run
  end

  defp locked_approval_attempt!(repo, attempt_id, context) do
    row = one(repo, "SELECT a.*,r.owner_type,r.owner_id FROM fount_run_approval_attempts a JOIN fount_runs r ON r.id=a.run_id WHERE a.id=$1::text::uuid FOR UPDATE", [attempt_id]) || rollback(repo, :not_found)
    :ok = or_rollback(repo, ActorContext.authorize(context, :manage_run, row["screenplay_id"]))
    if {row["owner_type"], row["owner_id"]} != {Atom.to_string(context.owner.type), context.owner.id}, do: rollback(repo, :unauthorized)
    row
  end

  defp authorize_row(context, run, permission \\ :read_run) do
    with :ok <- ActorContext.authorize(context, permission, run["screenplay_id"]),
         true <- {run["owner_type"], run["owner_id"]} == {Atom.to_string(context.owner.type), context.owner.id} do
      :ok
    else
      false -> {:error, :unauthorized}
      {:error, _} = error -> error
    end
  end

  defp verify_base(repo, screenplay_id, revision_id) do
    case one(repo, "SELECT id::text FROM revisions WHERE screenplay_id=$1::text::uuid AND id=$2::text::uuid", [screenplay_id, revision_id]) do
      nil -> {:error, :invalid_base_revision}
      _ -> :ok
    end
  end
  defp verify_base_or_rollback(repo, screenplay_id, revision_id), do: case verify_base(repo, screenplay_id, revision_id) do :ok -> :ok; {:error, reason} -> rollback(repo, reason) end

  defp append_event_locked(repo, run, plan_version, policy_version, principal, type, payload, binding \ %{}) do
    seq = one(repo, "SELECT COALESCE(MAX(sequence),0)+1 AS sequence FROM fount_run_events WHERE run_id=$1::text::uuid", [run["id"]])["sequence"]
    fp = CanonicalJSON.hash(payload)
    step_id = Map.get(binding, :step_id)
    attempt_number = Map.get(binding, :attempt_number)

    q!(repo, "INSERT INTO fount_run_events(id,run_id,screenplay_id,sequence,step_id,attempt_number,actor_type,actor_id,plan_version,policy_version,event_type,payload,payload_fingerprint,safe_summary) VALUES($1::text::uuid,$2::text::uuid,$3::text::uuid,$4,$5::text::uuid,$6,$7,$8,$9,$10,$11,$12::jsonb,$13,$14)", [ID.v4(), run["id"], run["screenplay_id"], seq, step_id, attempt_number, Atom.to_string(principal.type), principal.id, plan_version, policy_version, type, payload, fp, type])
    one(repo, "SELECT * FROM fount_run_events WHERE run_id=$1::text::uuid AND sequence=$2", [run["id"], seq])
  end

  defp run_row(repo, id), do: one(repo, "SELECT * FROM fount_runs WHERE id=$1::text::uuid", [id])
  defp plan_row(repo, run_id, version), do: one(repo, "SELECT * FROM fount_run_plans WHERE run_id=$1::text::uuid AND version=$2", [run_id, version])
  defp policy_row(repo, run_id, version), do: one(repo, "SELECT * FROM fount_run_policies WHERE run_id=$1::text::uuid AND version=$2", [run_id, version])
  defp step_row(repo, id), do: one(repo, "SELECT * FROM fount_run_steps WHERE id=$1::text::uuid", [id])
  defp attempt_row(repo, step_id, attempt_number), do: one(repo, "SELECT * FROM fount_run_attempts WHERE step_id=$1::text::uuid AND attempt_number=$2", [step_id, attempt_number])
  defp decision_row(repo, id), do: one(repo, "SELECT * FROM fount_run_decisions WHERE id=$1::text::uuid", [id])
  defp approval_attempt_row(repo, id), do: one(repo, "SELECT * FROM fount_run_approval_attempts WHERE id=$1::text::uuid", [id])
  defp usage_row(repo, id), do: one(repo, "SELECT * FROM fount_run_usage WHERE id=$1::text::uuid", [id])
  defp delivery_row(repo, id), do: one(repo, "SELECT * FROM fount_run_deliveries WHERE id=$1::text::uuid", [id])

  defp validate_start_opts([]), do: :ok
  defp validate_start_opts(_), do: {:error, :invalid_start_options}

  defp nonempty(map, key) do
    value = Map.get(map, key)
    if is_binary(value) and String.trim(value) != "", do: {:ok, value}, else: {:error, {:invalid_field, key}}
  end
  defp limit(value) when is_integer(value) and value > 0 and value <= 500, do: {:ok, value}
  defp limit(_), do: {:error, :invalid_limit}
  defp optional_enum(map, key, allowed), do: case Map.get(map, key) do nil -> :ok; value -> if value in allowed, do: :ok, else: {:error, {:invalid_field, key}} end
  defp maybe_filter(conditions, params, _key, nil), do: {conditions, params}
  defp maybe_filter(conditions, params, key, value), do: {conditions ++ ["#{key}=$#{length(params)+1}"], params ++ [value]}

  defp transaction(repo, fun) do
    case repo.transaction(fun) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _error in Postgrex.Error -> {:error, :storage_error}
  end

  defp storage_safe(fun) do
    fun.()
  rescue
    _error in Postgrex.Error -> {:error, :storage_error}
  end

  defp rollback(repo, reason), do: repo.rollback(reason)
  defp or_rollback(repo, :ok), do: :ok
  defp or_rollback(_repo, {:ok, value}), do: {:ok, value}
  defp or_rollback(repo, {:error, reason}), do: rollback(repo, reason)

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

  defp row_map(columns, row) do
    columns
    |> Enum.zip(row)
    |> Map.new(fn
      {column, <<_::binary-size(16)>> = value} when column in @uuid_columns ->
        case Ecto.UUID.load(value) do
          {:ok, uuid} -> {column, uuid}
          :error -> {column, value}
        end

      pair ->
        pair
    end)
  end
end
