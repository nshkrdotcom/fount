defmodule FountRun.DecisionCommand do
  @moduledoc "Exact Phase 05 decision submission with replay, binding, approval, replacement, and rebase semantics."

  alias Ecto.Adapters.SQL
  alias Fount.ID
  alias Fount.Persistence, as: CorePersistence
  alias Fount.Screenplay.Model
  alias Fount.Writing.{Approval, CanonicalJSON, Principal, Review}
  alias FountRun.{ActorContext, ApprovalBridge, Control, Persistence}

  @final_keys ~w(choice context_fingerprint plan_version policy_version findings overrides replacement_fountain)
  @rebase_keys ~w(choice context_fingerprint plan_version policy_version resolutions)
  @checkpoint_keys ~w(choice context_fingerprint plan_version policy_version)

  def submit(repo, decision_id, response, %ActorContext{} = context) do
    with true <- FountRun.ClosedMap.uuid_string(decision_id) or {:error, :invalid_decision_id},
         %{} = row <-
           one(repo, "SELECT kind FROM fount_run_decisions WHERE id=$1::text::uuid", [decision_id]) ||
             {:error, :not_found} do
      case row["kind"] do
        "strategy" -> Persistence.submit_strategy_decision(repo, decision_id, response, context)
        "final_approval" -> submit_final(repo, decision_id, response, context)
        "rebase" -> submit_rebase(repo, decision_id, response, context)
        "candidate_review" -> resume_phase04_candidate(repo, decision_id, response, context)
        "iteration" -> resume_iteration(repo, decision_id, response, context)
        _ -> Persistence.resolve_decision(repo, decision_id, response, context)
      end
    else
      {:error, _} = error -> error
    end
  rescue
    _ in Postgrex.Error -> {:error, :storage_error}
  end

  def approve_run(repo, run_id, attrs, %ActorContext{} = context)
      when is_binary(run_id) and is_map(attrs) do
    attrs = stringify_keys(attrs)

    with decision_id when is_binary(decision_id) <- attrs["decision_id"],
         context_fingerprint when is_binary(context_fingerprint) <- attrs["context_fingerprint"],
         plan_version when is_integer(plan_version) <- attrs["plan_version"],
         policy_version when is_integer(policy_version) <- attrs["policy_version"] do
      response = %{
        "choice" => "approve",
        "context_fingerprint" => context_fingerprint,
        "plan_version" => plan_version,
        "policy_version" => policy_version,
        "findings" => attrs["findings"] || [],
        "overrides" => attrs["overrides"] || []
      }

      case one(repo, "SELECT run_id::text FROM fount_run_decisions WHERE id=$1::text::uuid", [
             decision_id
           ]) do
        %{"run_id" => ^run_id} -> submit(repo, decision_id, response, context)
        %{"run_id" => _} -> {:error, :cross_run_decision}
        nil -> {:error, :not_found}
      end
    else
      _ -> {:error, :exact_decision_binding_required}
    end
  rescue
    _ in Postgrex.Error -> {:error, :storage_error}
  end

  def approve_run(_repo, _run_id, _attrs, _context),
    do: {:error, :exact_decision_binding_required}

  defp submit_final(repo, decision_id, response, context) do
    with {:ok, response} <- normalize(response, @final_keys),
         true <-
           response["choice"] in ["approve", "reject", "replace"] or
             {:error, :invalid_decision_choice},
         :ok <- decision_response_shape(response),
         {:ok, prepared} <- prepare_final(repo, decision_id, response, context) do
      case prepared do
        %{"outcome" => "rejected"} = result ->
          {:ok, result}

        %{"outcome" => "replacement"} = result ->
          {:ok, result}

        %{"approval_attempt_id" => attempt_id, "replay" => replay} ->
          accept_final_attempt(repo, attempt_id, context, replay)
      end
    else
      {:error, _} = error -> error
    end
  end

  defp accept_final_attempt(repo, attempt_id, context, replay) do
    case ApprovalBridge.accept_ready(repo, attempt_id, context) do
      {:ok, accepted} -> {:ok, Map.put(accepted, "decision_replay", replay)}
      other -> other
    end
  end

  defp prepare_final(repo, decision_id, response, context) do
    tx(repo, fn -> prepare_final_locked!(repo, decision_id, response, context) end)
  end

  defp prepare_final_locked!(repo, decision_id, response, context) do
    {decision, run} = locked_decision_and_run!(repo, decision_id, context)
    verify_exact_binding!(repo, decision, run, response, context, "final_approval")
    response_fp = CanonicalJSON.hash(response)
    replay = resolved_replay?(repo, decision, response_fp, context)

    if decision["status"] == "pending" do
      case Persistence.resolve_decision(repo, decision_id, response, context) do
        {:ok, _} -> :ok
        {:error, reason} -> rollback(repo, normalize_conflict(reason))
      end
    end

    if response["choice"] == "replace" do
      replace_candidate!(repo, decision, run, response, response_fp, context, replay)
    else
      prepare_reviewed_final!(
        repo,
        decision_id,
        decision,
        run,
        response,
        response_fp,
        context,
        replay
      )
    end
  end

  defp prepare_reviewed_final!(
         repo,
         decision_id,
         decision,
         run,
         response,
         response_fp,
         context,
         replay
       ) do
    packet = exact_packet!(repo, decision)
    parent_attempt_id = decision_parent_attempt(decision)
    recommendation = if response["choice"] == "approve", do: "approve", else: "reject"
    approver = context.principal

    attempt =
      ensure_human_attempt!(repo, decision, run, packet, parent_attempt_id, approver, context)

    review =
      unwrap!(
        repo,
        Review.new(
          reviewer: approver,
          candidate_id: packet["candidate_id"],
          base_revision_id: packet["base_revision_id"],
          content_hash: packet["content_hash"],
          report_ids: packet["report_ids"] || [],
          check_set_fingerprint: packet["check_set_fingerprint"],
          findings: response["findings"] || [],
          recommendation: recommendation,
          overrides: response["overrides"] || []
        )
      )

    saved =
      unwrap!(
        repo,
        Persistence.record_approval_review(
          repo,
          attempt["id"],
          review,
          recommendation,
          context
        )
      )

    final = %{
      decision_id: decision_id,
      decision: decision,
      run: run,
      packet: packet,
      response_fp: response_fp,
      context: context,
      replay: replay,
      review: review,
      saved: saved
    }

    if recommendation == "reject",
      do: reject_final!(repo, final, attempt),
      else: ready_final!(repo, final)
  end

  defp reject_final!(repo, final, attempt) do
    rejected =
      unwrap!(
        repo,
        Persistence.record_approval_outcome(
          repo,
          attempt["id"],
          "rejected",
          "human_rejected",
          final.context
        )
      )

    unless final.replay do
      q!(
        repo,
        "UPDATE fount_runs SET status='partial',stage='decide',lock_version=lock_version+1,updated_at=now() WHERE id=$1::text::uuid",
        [final.run["id"]]
      )

      event!(repo, final.run["id"], final.context, "final_candidate_rejected", %{
        "decision_id" => final.decision_id,
        "approval_attempt_id" => rejected["id"]
      })
    end

    %{
      "decision_id" => final.decision_id,
      "approval_attempt_id" => rejected["id"],
      "candidate_id" => final.packet["candidate_id"],
      "outcome" => "rejected",
      "replay" => final.replay
    }
  end

  defp ready_final!(repo, final) do
    approval_id =
      final.saved["approval_id"] || ID.v5(final.decision_id, ["approval:", final.response_fp])

    approval =
      unwrap!(
        repo,
        Approval.new(
          id: approval_id,
          approver: final.context.principal,
          screenplay_id: final.run["screenplay_id"],
          candidate_id: final.packet["candidate_id"],
          base_revision_id: final.packet["base_revision_id"],
          content_hash: final.packet["content_hash"],
          review: final.review,
          run_id: final.run["id"],
          run_policy_version: final.decision["policy_version"],
          run_policy_fingerprint: final.run["policy"]["fingerprint"]
        )
      )

    ready =
      unwrap!(
        repo,
        Persistence.record_approval_payload(
          repo,
          final.saved["id"],
          approval_id,
          approval,
          final.context
        )
      )

    unless final.replay do
      q!(
        repo,
        "UPDATE fount_runs SET status='waiting_for_approval',stage='decide',lock_version=lock_version+1,updated_at=now() WHERE id=$1::text::uuid",
        [final.run["id"]]
      )

      event!(repo, final.run["id"], final.context, "final_approval_ready", %{
        "decision_id" => final.decision_id,
        "approval_attempt_id" => ready["id"],
        "approval_id" => approval_id
      })
    end

    %{
      "decision_id" => final.decision_id,
      "approval_attempt_id" => ready["id"],
      "approval_id" => approval_id,
      "candidate_id" => final.packet["candidate_id"],
      "outcome" => "ready",
      "replay" => final.replay
    }
  end

  defp replace_candidate!(repo, decision, run, response, response_fp, context, replay) do
    source = response["replacement_fountain"]

    if not (is_binary(source) and String.trim(source) != ""),
      do: rollback(repo, :replacement_text_required)

    candidate_id = ID.v5(decision["id"], ["replacement:", response_fp])

    case CorePersistence.candidate(repo, candidate_id) do
      {:ok, existing} ->
        replacement_result(
          decision,
          existing,
          replay,
          existing_step(repo, run["id"], "replacement:" <> decision["id"] <> ":check")
        )

      {:error, :not_found} ->
        save_new_replacement!(repo, decision, run, source, candidate_id, context, replay)
    end
  end

  defp save_new_replacement!(repo, decision, run, source, candidate_id, context, replay) do
    current =
      case CorePersistence.load_revision(
             repo,
             run["screenplay_id"],
             decision["base_revision_id"]
           ) do
        {:ok, value} -> value
        {:error, reason} -> rollback(repo, reason)
      end

    doc =
      case Fount.parse(source,
             document_id: current.id,
             parent_revision_id: current.revision.id,
             actor: context.principal.id,
             message: "Run final-decision replacement"
           ) do
        {:ok, value} -> value
        {:error, reason} -> rollback(repo, {:invalid_replacement_fountain, reason})
      end

    draft =
      doc
      |> Fount.Screenplay.from_document()
      |> Map.put(:revision, doc.revision)
      |> Map.put(:import, nil)
      |> Model.refresh()

    key =
      one(repo, "SELECT key FROM screenplays WHERE id=$1::text::uuid", [run["screenplay_id"]])[
        "key"
      ]

    replacement =
      case CorePersistence.save_edit_candidate(repo, key, draft,
             expected_revision: current.revision.id,
             candidate_id: candidate_id,
             session_id: ID.v5(decision["id"], "replacement-session"),
             label: "Run human replacement",
             operations: []
           ) do
        {:ok, value} -> value
        {:error, reason} -> rollback(repo, reason)
      end

    request =
      step_request(repo, decision["step_id"]) ||
        rollback(repo, :decision_step_request_missing)

    step =
      create_step!(
        repo,
        run,
        "check",
        request,
        replacement["id"],
        "replacement:" <> decision["id"] <> ":check",
        context
      )

    q!(
      repo,
      "UPDATE fount_runs SET selected_candidate_id=$2::text::uuid,status='queued',stage='check',updated_at=now() WHERE id=$1::text::uuid",
      [run["id"], replacement["id"]]
    )

    event!(repo, run["id"], context, "human_replacement_candidate_saved", %{
      "decision_id" => decision["id"],
      "candidate_id" => replacement["id"],
      "check_step_id" => step["id"]
    })

    replacement_result(decision, replacement, replay, step)
  end

  defp replacement_result(decision, candidate, replay, step) do
    %{
      "decision_id" => decision["id"],
      "candidate_id" => candidate["id"],
      "check_step_id" => step && step["id"],
      "outcome" => "replacement",
      "replay" => replay,
      "changes_canon" => false
    }
  end

  defp submit_rebase(repo, decision_id, response, context) do
    with {:ok, response} <- normalize(response, @rebase_keys),
         true <- response["choice"] in ["rebase", "stop"] or {:error, :invalid_decision_choice},
         :ok <- decision_response_shape(response) do
      tx(repo, fn -> submit_rebase_locked!(repo, decision_id, response, context) end)
    else
      {:error, _} = error -> error
    end
  end

  defp submit_rebase_locked!(repo, decision_id, response, context) do
    {decision, run} = locked_decision_and_run!(repo, decision_id, context)
    verify_exact_binding!(repo, decision, run, response, context, "rebase")
    _ = exact_packet!(repo, decision)
    response_fp = CanonicalJSON.hash(response)
    replay = resolved_replay?(repo, decision, response_fp, context)

    if decision["status"] == "pending" do
      case Persistence.resolve_decision(repo, decision_id, response, context) do
        {:ok, _} -> :ok
        {:error, reason} -> rollback(repo, normalize_conflict(reason))
      end
    end

    if response["choice"] == "stop" do
      case Control.stop(repo, run["id"], context) do
        {:ok, value} -> Map.merge(value, %{"decision_id" => decision_id, "replay" => replay})
        {:error, reason} -> rollback(repo, reason)
      end
    else
      rebase_candidate!(repo, decision, run, response, response_fp, context, replay)
    end
  end

  defp rebase_candidate!(repo, decision, run, response, response_fp, context, replay) do
    resolutions = response["resolutions"] || %{"choices" => %{}}
    {:ok, head_id} = Control.current_head(repo, run["screenplay_id"])

    current = unwrap!(repo, CorePersistence.load_revision(repo, run["screenplay_id"], head_id))

    services = %{store: FountWorkshop.Store.new(repo)}

    rebased =
      rebase_result!(
        repo,
        FountWorkshop.Rebase.run(decision["candidate_id"], current, resolutions, services)
      )

    successor_key = "rebase-successor:" <> decision_id_short(decision["id"], response_fp)
    plan = run["plan"]
    policy = run["policy"]

    attrs = %{
      "screenplay_id" => run["screenplay_id"],
      "base_revision_id" => current.revision.id,
      "goal" => plan["goal"],
      "scope" => plan["scope"],
      "constraints" => plan["constraints"],
      "protected_material" => plan["protected_material"],
      "input_brief" => plan["input_brief"],
      "input_notes" => plan["input_notes"],
      "operation_parameters" => plan["operation_parameters"],
      "policy" => policy["policy"],
      "client_idempotency_key" => successor_key
    }

    successor = unwrap!(repo, Persistence.start_run(repo, attrs, context))

    q!(
      repo,
      "UPDATE fount_runs SET superseding_run_id=$2::text::uuid,current_fencing_token=current_fencing_token+1,status='partial',updated_at=now() WHERE id=$1::text::uuid",
      [run["id"], successor["id"]]
    )

    q!(
      repo,
      "UPDATE fount_runs SET parent_run_id=$2::text::uuid,selected_candidate_id=$3::text::uuid,iteration=$4,status='queued',stage='check',updated_at=now() WHERE id=$1::text::uuid",
      [successor["id"], run["id"], rebased["id"], run["iteration"] || 0]
    )

    request =
      step_request(repo, decision["step_id"]) || rollback(repo, :decision_step_request_missing)

    request = put_workshop_base(request, current.revision.id)

    step =
      create_step!(
        repo,
        successor,
        "check",
        request,
        rebased["id"],
        "rebase:" <> decision["id"] <> ":check",
        context
      )

    event!(repo, run["id"], context, "run_rebased_to_successor", %{
      "decision_id" => decision["id"],
      "successor_run_id" => successor["id"],
      "candidate_id" => rebased["id"]
    })

    %{
      "decision_id" => decision["id"],
      "run_id" => successor["id"],
      "parent_run_id" => run["id"],
      "candidate_id" => rebased["id"],
      "check_step_id" => step["id"],
      "outcome" => "rebased",
      "replay" => replay,
      "changes_canon" => false
    }
  end

  defp rebase_result!(_repo, {:ok, %{"id" => _} = candidate}), do: candidate

  defp rebase_result!(repo, {:ok, %{"status" => "no_change"}}),
    do: rollback(repo, :rebase_no_candidate)

  defp rebase_result!(repo, {:error, reason}), do: rollback(repo, reason)

  defp resume_iteration(repo, decision_id, response, context) do
    with {:ok, response} <- normalize(response, @checkpoint_keys),
         true <- response["choice"] == "review" or {:error, :invalid_decision_choice},
         :ok <- decision_response_shape(response) do
      tx(repo, fn -> resume_iteration_locked!(repo, decision_id, response, context) end)
    else
      {:error, _} = error -> error
    end
  end

  defp resume_iteration_locked!(repo, decision_id, response, context) do
    {decision, run} = locked_decision_and_run!(repo, decision_id, context)
    verify_exact_binding!(repo, decision, run, response, context, "iteration")
    ensure_run_check!(repo, decision)
    response_fp = CanonicalJSON.hash(response)
    replay = resolved_replay?(repo, decision, response_fp, context)

    if decision["status"] == "pending" do
      case Persistence.resolve_decision(repo, decision_id, response, context) do
        {:ok, _} -> :ok
        {:error, reason} -> rollback(repo, normalize_conflict(reason))
      end
    end

    key = "iteration-review:" <> decision_id <> ":decide"
    step = existing_step(repo, run["id"], key)

    step =
      step ||
        create_step!(
          repo,
          run,
          "decide",
          step_request(repo, decision["step_id"]),
          decision["candidate_id"],
          key,
          context
        )

    q!(
      repo,
      "UPDATE fount_runs SET selected_candidate_id=$2::text::uuid,status='queued',stage='decide',updated_at=now() WHERE id=$1::text::uuid",
      [run["id"], decision["candidate_id"]]
    )

    %{
      "decision_id" => decision_id,
      "next_step_id" => step["id"],
      "candidate_id" => decision["candidate_id"],
      "replay" => replay,
      "status" => "queued"
    }
  end

  defp resume_phase04_candidate(repo, decision_id, response, context) do
    tx(repo, fn -> resume_phase04_candidate_locked!(repo, decision_id, response, context) end)
  end

  defp resume_phase04_candidate_locked!(repo, decision_id, response, context) do
    {decision, run} = locked_decision_and_run!(repo, decision_id, context)
    response = stringify_keys(response)

    if response["choice"] not in ["review", "continue"],
      do: rollback(repo, :invalid_decision_choice)

    response =
      response
      |> Map.put_new("context_fingerprint", decision["context_fingerprint"])
      |> Map.put_new("plan_version", decision["plan_version"])
      |> Map.put_new("policy_version", decision["policy_version"])

    verify_exact_binding!(repo, decision, run, response, context, "candidate_review")
    response_fp = CanonicalJSON.hash(response)
    replay = resolved_replay?(repo, decision, response_fp, context)

    if decision["status"] == "pending" do
      case Persistence.resolve_decision(repo, decision_id, response, context) do
        {:ok, _} -> :ok
        {:error, reason} -> rollback(repo, normalize_conflict(reason))
      end
    end

    key = "phase04-upgrade:" <> decision_id <> ":decide"
    step = existing_step(repo, run["id"], key)

    step =
      step ||
        create_step!(
          repo,
          run,
          "decide",
          step_request(repo, decision["step_id"]),
          decision["candidate_id"],
          key,
          context
        )

    q!(
      repo,
      "UPDATE fount_runs SET status='queued',stage='decide',updated_at=now() WHERE id=$1::text::uuid",
      [run["id"]]
    )

    %{
      "decision_id" => decision_id,
      "next_step_id" => step["id"],
      "replay" => replay,
      "status" => "queued"
    }
  end

  defp ensure_human_attempt!(repo, decision, run, packet, parent_attempt_id, approver, context) do
    attrs = %{
      "step_id" => decision["step_id"],
      "decision_id" => decision["id"],
      "parent_attempt_id" => parent_attempt_id,
      "candidate_id" => packet["candidate_id"],
      "base_revision_id" => packet["base_revision_id"],
      "content_hash" => packet["content_hash"],
      "check_set_fingerprint" => packet["check_set_fingerprint"],
      "packet" =>
        scrub_packet(
          Map.put(packet, "run_check_set_fingerprint", decision["check_set_fingerprint"])
        ),
      "packet_artifact_ref" => nil,
      "reviewer" => Principal.to_map(approver),
      "approver" => Principal.to_map(approver),
      "callback_operation_id" => "human-final:" <> decision["id"],
      "fencing_token" => run["current_fencing_token"]
    }

    case Persistence.create_approval_attempt(repo, run["id"], attrs, context) do
      {:ok, value} -> value
      {:error, reason} -> rollback(repo, reason)
    end
  end

  defp exact_packet!(repo, decision) do
    packet =
      case FountWorkshop.Review.packet(repo, decision["candidate_id"]) do
        {:ok, value} -> value
        {:error, reason} -> rollback(repo, reason)
      end

    cond do
      packet["candidate_id"] != decision["candidate_id"] ->
        rollback(repo, :stale_decision_candidate)

      packet["base_revision_id"] != decision["base_revision_id"] ->
        rollback(repo, :stale_decision_base)

      packet["content_hash"] != decision["content_hash"] ->
        rollback(repo, :stale_decision_content)

      true ->
        ensure_run_check!(repo, decision)
        packet
    end
  end

  defp ensure_run_check!(repo, decision) do
    row =
      one(
        repo,
        "SELECT id::text FROM fount_run_steps WHERE run_id=$1::text::uuid AND stage='check' AND status='succeeded' AND plan_version=$2 AND policy_version=$3 AND result->>'candidate_id'=$4 AND result->>'check_set_fingerprint'=$5 ORDER BY completed_at DESC,id DESC LIMIT 1",
        [
          decision["run_id"],
          decision["plan_version"],
          decision["policy_version"],
          decision["candidate_id"],
          decision["check_set_fingerprint"]
        ]
      )

    if is_nil(row), do: rollback(repo, :fresh_check_required), else: :ok
  end

  defp verify_exact_binding!(repo, decision, run, response, context, expected_kind) do
    expected_principal = {decision["authorized_type"], decision["authorized_id"]}
    actual_principal = {Atom.to_string(context.principal.type), context.principal.id}

    cond do
      decision["kind"] != expected_kind ->
        rollback(repo, :unsupported_decision_kind)

      expected_principal != actual_principal ->
        rollback(repo, :unauthorized)

      response["context_fingerprint"] != decision["context_fingerprint"] ->
        rollback(repo, :stale_decision_context)

      true ->
        verify_binding_versions!(repo, decision, run, response)
    end
  end

  defp verify_binding_versions!(repo, decision, run, response) do
    cond do
      response["plan_version"] != decision["plan_version"] ->
        rollback(repo, :stale_decision_binding)

      response["policy_version"] != decision["policy_version"] ->
        rollback(repo, :stale_decision_binding)

      run["current_plan_version"] != decision["plan_version"] ->
        rollback(repo, :stale_decision)

      run["current_policy_version"] != decision["policy_version"] ->
        rollback(repo, :stale_decision)

      true ->
        verify_binding_control!(repo, run)
    end
  end

  defp verify_binding_control!(repo, run) do
    cond do
      run["stop_requested_at"] ->
        rollback(repo, :stopped)

      run["pause_requested_at"] ->
        rollback(repo, :paused)

      true ->
        :ok
    end
  end

  defp resolved_replay?(repo, decision, response_fp, context) do
    cond do
      decision["status"] == "pending" ->
        false

      decision["status"] == "resolved" and decision["response_fingerprint"] == response_fp and
        decision["respondent_type"] == Atom.to_string(context.principal.type) and
          decision["respondent_id"] == context.principal.id ->
        true

      decision["status"] == "resolved" ->
        rollback(repo, :decision_conflict)

      true ->
        rollback(repo, :stale_decision)
    end
  end

  defp locked_decision_and_run!(repo, decision_id, context) do
    identity =
      one(repo, "SELECT run_id::text FROM fount_run_decisions WHERE id=$1::text::uuid", [
        decision_id
      ]) ||
        rollback(repo, :not_found)

    # Global Phase-05 lock order is Run -> screenplay -> candidate. Decision rows are
    # subordinate to the Run and are therefore locked only after the Run row.
    run =
      one(repo, "SELECT * FROM fount_runs WHERE id=$1::text::uuid FOR UPDATE", [
        identity["run_id"]
      ]) ||
        rollback(repo, :not_found)

    authorize_run!(repo, run, context)

    decision =
      one(repo, "SELECT d.* FROM fount_run_decisions d WHERE d.id=$1::text::uuid FOR UPDATE", [
        decision_id
      ]) ||
        rollback(repo, :not_found)

    if decision["run_id"] != run["id"], do: rollback(repo, :cross_run_decision)
    {decision, hydrate_run(repo, run)}
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

  defp decision_response_shape(response) do
    cond do
      not is_binary(response["context_fingerprint"]) ->
        {:error, :exact_decision_binding_required}

      not is_integer(response["plan_version"]) or response["plan_version"] < 1 ->
        {:error, :exact_decision_binding_required}

      not is_integer(response["policy_version"]) or response["policy_version"] < 1 ->
        {:error, :exact_decision_binding_required}

      true ->
        :ok
    end
  end

  defp decision_parent_attempt(decision) do
    decision["options"]
    |> List.wrap()
    |> Enum.find_value(fn option -> option["parent_attempt_id"] end)
  end

  defp create_step!(repo, run, stage, request, candidate_id, key, context) do
    attrs = %{
      "stage" => stage,
      "iteration" => run["iteration"] || 0,
      "branch_id" => "main",
      "input_revision_id" => nil,
      "input_candidate_id" => candidate_id,
      "request" => request,
      "idempotency_key" => key
    }

    case Persistence.create_step(repo, run["id"], attrs, context) do
      {:ok, value} -> value
      {:error, reason} -> rollback(repo, reason)
    end
  end

  defp step_request(_repo, nil), do: nil

  defp step_request(repo, id),
    do:
      one(repo, "SELECT request FROM fount_run_steps WHERE id=$1::text::uuid", [id])
      |> then(&(&1 && &1["request"]))

  defp existing_step(repo, run_id, key),
    do:
      one(
        repo,
        "SELECT * FROM fount_run_steps WHERE run_id=$1::text::uuid AND idempotency_key=$2",
        [run_id, key]
      )

  defp put_workshop_base(%{"workshop_request" => request} = envelope, base) when is_map(request),
    do: Map.put(envelope, "workshop_request", Map.put(request, "base_revision_id", base))

  defp put_workshop_base(envelope, _base), do: envelope

  defp normalize(value, allowed) when is_map(value) do
    value = stringify_keys(value)

    if Map.keys(value) -- allowed == [],
      do: {:ok, value},
      else: {:error, :unknown_decision_response_field}
  end

  defp normalize(_, _), do: {:error, :invalid_decision_response}

  defp scrub_packet(packet),
    do: packet |> Map.drop(["original_fountain", "proposed_fountain"]) |> Model.plain()

  defp normalize_conflict(:already_resolved), do: :decision_conflict
  defp normalize_conflict(reason), do: reason
  defp decision_id_short(id, fp), do: String.slice(id, 0, 8) <> ":" <> String.slice(fp, 0, 12)

  defp event!(repo, run_id, context, type, payload) do
    case Persistence.append_event(repo, run_id, type, payload, context) do
      {:ok, value} -> value
      {:error, reason} -> rollback(repo, reason)
    end
  end

  defp hydrate_run(repo, run) do
    plan =
      one(repo, "SELECT * FROM fount_run_plans WHERE run_id=$1::text::uuid AND version=$2", [
        run["id"],
        run["current_plan_version"]
      ])

    policy =
      one(repo, "SELECT * FROM fount_run_policies WHERE run_id=$1::text::uuid AND version=$2", [
        run["id"],
        run["current_policy_version"]
      ])

    run |> Map.put("plan", plan) |> Map.put("policy", policy)
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
  defp stringify_keys(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
end
