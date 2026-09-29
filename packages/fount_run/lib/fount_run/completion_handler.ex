defmodule FountRun.CompletionHandler do
  @moduledoc "Phase 05 completion gate: stale-base handling, candidate completion, and canonical approval."
  @behaviour FountRun.StageHandler

  alias Fount.Writing.Principal
  alias FountRun.{ActorContext, ApprovalBridge, Control, Persistence}

  @impl true
  def execute(%{"stage" => "decide"} = claim, opts) do
    repo = Keyword.fetch!(opts, :repo)
    context = Keyword.fetch!(opts, :actor_context)
    candidate_id = claim["input_candidate_id"]

    with true <- is_binary(candidate_id) or {:error, :candidate_required},
         {:ok, run} <- FountRun.get_run(repo, claim["run_id"], context),
         {:ok, packet} <- FountWorkshop.Review.packet(repo, candidate_id),
         :ok <- exact_candidate(run, packet, candidate_id),
         {:ok, run_check} <- latest_fresh_check(repo, run, candidate_id, context),
         packet = Map.put(packet, "run_check_set_fingerprint", run_check["check_set_fingerprint"]),
         {:ok, head_revision_id} <- Control.current_head(repo, run["screenplay_id"]) do
      if head_revision_id == packet["base_revision_id"] do
        decide_current(
          repo,
          claim,
          run,
          packet,
          context,
          opts
          |> Keyword.put(:run_check_set_fingerprint, run_check["check_set_fingerprint"])
          |> Keyword.put(:run_check, run_check)
        )
      else
        stale_checkpoint(repo, claim, run, packet, head_revision_id, context)
      end
    else
      {:error, _} = error -> error
    end
  end

  def execute(_claim, _opts), do: {:error, :unsupported_completion_stage}

  defp decide_current(repo, claim, run, packet, context, opts) do
    policy = get_in(run, ["policy", "policy"]) || %{}

    case policy["completion"] do
      "candidate" ->
        with :ok <- completion_check_gate(opts[:run_check], packet, :candidate) do
          {:ok,
           result(packet)
           |> Map.merge(%{
             "status" => "candidate_ready_for_delivery",
             "run_status" => "partial",
             "next_stage" => "deliver",
             "changes_canon" => false
           })}
        end

      "accept" ->
        accept_current(repo, claim, run, packet, context, opts, policy)

      _ ->
        {:error, :invalid_completion_policy}
    end
  end

  defp accept_current(repo, claim, run, packet, context, opts, policy) do
    with {:ok, approver} <- Principal.from_map(policy["approver"] || %{}),
         :ok <- completion_check_gate(opts[:run_check], packet, approver.type) do
      case approver.type do
        :human ->
          human_checkpoint(repo, claim, run, packet, approver, context, nil)

        type when type in [:agent, :service] ->
          automated(repo, claim, run, packet, approver, context, opts)
      end
    end
  end

  defp automated(repo, claim, run, packet, approver, context, opts) do
    with %ActorContext{} = approval_context <- Keyword.get(opts, :approval_context),
         callback when is_function(callback, 1) <- Keyword.get(opts, :approval_callback),
         true <-
           same_principal?(approval_context.principal, approver) or {:error, :wrong_approver} do
      approval_opts =
        opts
        |> Keyword.put(:step_id, claim["step_id"])
        |> Keyword.put(:defer_run_completion, true)

      case ApprovalBridge.automated(
             repo,
             run,
             packet["candidate_id"],
             context,
             approval_context,
             callback,
             approval_opts
           ) do
        {:ok, %{"status" => "accepted"} = accepted} ->
          {:ok,
           result(packet)
           |> Map.merge(%{
             "status" => "accepted_pending_delivery",
             "run_status" => "partial",
             "next_stage" => "deliver",
             "acceptance_id" => accepted["acceptance_id"],
             "approval_id" => accepted["approval_id"],
             "changes_canon" => true
           })}

        {:ok, %{"outcome" => "rejected"} = attempt} ->
          fallback_or_partial(
            repo,
            claim,
            run,
            packet,
            context,
            attempt["id"],
            "reviewer_rejected"
          )

        {:partial, :approval_outcome_unknown, details} ->
          fallback_or_partial(
            repo,
            claim,
            run,
            packet,
            context,
            details["approval_attempt_id"],
            "approval_outcome_unknown"
          )

        {:partial, :approval_paused, details} ->
          {:partial, :approval_paused, Map.put(details, "candidate_id", packet["candidate_id"])}

        {:error, reason} ->
          fallback_or_partial(repo, claim, run, packet, context, nil, reason)

        other ->
          {:error, {:invalid_approval_result, other}}
      end
    else
      nil -> {:error, :approval_context_required}
      false -> {:error, :approval_callback_required}
      {:error, _} = error -> error
      _ -> {:error, :approval_callback_required}
    end
  end

  defp fallback_or_partial(repo, claim, run, packet, context, parent_attempt_id, reason) do
    fallback = get_in(run, ["policy", "policy", "fallback_approver"])

    case {fallback_allowed?(reason), fallback} do
      {true, %{}} ->
        start_human_fallback(repo, claim, run, packet, context, parent_attempt_id, fallback)

      _ ->
        {:partial, :approval_not_completed,
         %{"reason" => inspect(reason), "candidate_id" => packet["candidate_id"]}}
    end
  end

  defp start_human_fallback(repo, claim, run, packet, context, parent_attempt_id, fallback) do
    with {:ok, principal} <- Principal.from_map(fallback) do
      if parent_attempt_id do
        _ =
          Persistence.record_approval_outcome(
            repo,
            parent_attempt_id,
            "fenced",
            "fallback_started",
            context
          )
      end

      human_checkpoint(repo, claim, run, packet, principal, context, parent_attempt_id)
    end
  end

  defp fallback_allowed?({:core_acceptance_rejected, _}), do: false
  defp fallback_allowed?({:approval_attempt_terminal, "fenced", _}), do: false
  defp fallback_allowed?(:unregistered_approver), do: false
  defp fallback_allowed?(:wrong_approver), do: false
  defp fallback_allowed?(:paused), do: false
  defp fallback_allowed?(:stopped), do: false
  defp fallback_allowed?(:stale_plan), do: false
  defp fallback_allowed?(:stale_policy), do: false
  defp fallback_allowed?(:stale_fencing_token), do: false
  defp fallback_allowed?(_), do: true

  defp human_checkpoint(repo, claim, run, packet, approver, context, parent_attempt_id) do
    suffix = if parent_attempt_id, do: ":fallback:" <> parent_attempt_id, else: ""

    attrs = %{
      "checkpoint_key" =>
        "final-approval:" <>
          packet["candidate_id"] <>
          ":" <> to_string(run["current_policy_version"]) <> suffix,
      "kind" => "final_approval",
      "prompt" => "Approve or reject this exact checked candidate for canonical acceptance.",
      "options" => [
        %{
          "id" => "approve",
          "label" => "Accept candidate",
          "parent_attempt_id" => parent_attempt_id
        },
        %{
          "id" => "reject",
          "label" => "Keep candidate only",
          "parent_attempt_id" => parent_attempt_id
        },
        %{
          "id" => "replace",
          "label" => "Replace with edited Fountain and re-check",
          "parent_attempt_id" => parent_attempt_id
        }
      ],
      "step_id" => claim["step_id"],
      "candidate_id" => packet["candidate_id"],
      "base_revision_id" => packet["base_revision_id"],
      "content_hash" => packet["content_hash"],
      "check_set_fingerprint" =>
        packet["run_check_set_fingerprint"] || packet["check_set_fingerprint"],
      "authorized_principal" => Principal.to_map(approver)
    }

    with {:ok, decision} <- Persistence.put_pending_decision(repo, run["id"], attrs, context) do
      {:ok,
       result(packet)
       |> Map.merge(%{
         "status" => "waiting_for_final_approval",
         "run_status" => "waiting_for_decision",
         "next_stage" => "decide",
         "decision_id" => decision["id"],
         "decision_context_fingerprint" => decision["context_fingerprint"],
         "changes_canon" => false
       })}
    end
  end

  defp stale_checkpoint(repo, claim, run, packet, head_revision_id, context) do
    attrs = %{
      "checkpoint_key" =>
        "stale-base:" <>
          packet["candidate_id"] <>
          ":" <> head_revision_id <> ":" <> to_string(run["current_plan_version"]),
      "kind" => "rebase",
      "prompt" =>
        "Canonical head advanced after this candidate was composed. Compare explicitly and rebase before any approval.",
      "options" => [
        %{"id" => "rebase", "label" => "Rebase candidate onto current canon"},
        %{"id" => "stop", "label" => "Stop this run"}
      ],
      "step_id" => claim["step_id"],
      "candidate_id" => packet["candidate_id"],
      "base_revision_id" => packet["base_revision_id"],
      "content_hash" => packet["content_hash"],
      "check_set_fingerprint" =>
        packet["run_check_set_fingerprint"] || packet["check_set_fingerprint"],
      "authorized_principal" => Principal.to_map(context.owner)
    }

    with {:ok, decision} <- Persistence.put_pending_decision(repo, run["id"], attrs, context) do
      {:ok,
       result(packet)
       |> Map.merge(%{
         "status" => "stale_base",
         "run_status" => "waiting_for_decision",
         "next_stage" => "decide",
         "canonical_head_revision_id" => head_revision_id,
         "decision_id" => decision["id"],
         "decision_context_fingerprint" => decision["context_fingerprint"],
         "changes_canon" => false
       })}
    end
  end

  defp latest_fresh_check(repo, run, candidate_id, context) do
    with {:ok, progress} <- FountRun.progress(repo, run["id"], context),
         check when not is_nil(check) <-
           progress["steps"]
           |> Enum.reverse()
           |> Enum.find(fn step ->
             step["stage"] == "check" and step["status"] == "succeeded" and
               step["plan_version"] == run["current_plan_version"] and
               step["policy_version"] == run["current_policy_version"] and
               get_in(step, ["result", "candidate_id"]) == candidate_id
           end),
         result when is_map(result) <- check["result"],
         fingerprint when is_binary(fingerprint) <- result["check_set_fingerprint"] do
      {:ok, result}
    else
      nil -> {:error, :fresh_check_required}
      _ -> {:error, :fresh_check_required}
    end
  end

  # Run-owned deterministic checks are never overridable. Candidate checks may proceed to
  # a human final decision only when Core's immutable inventory declares the exact failed
  # semantic constraint overridable; Core still validates the submitted override reason.
  defp completion_check_gate(nil, _packet, _approver_type), do: {:error, :fresh_check_required}

  defp completion_check_gate(run_check, packet, approver_type) do
    required = Map.new(packet["required_checks"] || [], &{&1["constraint_id"], &1})

    blockers =
      Enum.filter(run_check["checks"] || [], fn check ->
        if check["severity"] == "required" and check["status"] in ["fail", "unknown"] do
          definition = required[check["constraint_id"]]

          not (approver_type == :human and is_map(definition) and
                 definition["evaluation"] == "semantic" and definition["overridable"] == true)
        else
          false
        end
      end)

    if blockers == [], do: :ok, else: {:error, {:required_check_blocked, blockers}}
  end

  defp exact_candidate(run, packet, candidate_id) do
    cond do
      packet["candidate_id"] != candidate_id ->
        {:error, :candidate_binding_mismatch}

      packet["screenplay_id"] != run["screenplay_id"] ->
        {:error, :candidate_screenplay_mismatch}

      packet["base_revision_id"] != get_in(run, ["plan", "base_revision_id"]) ->
        {:error, :candidate_plan_base_mismatch}

      not is_binary(packet["check_set_fingerprint"]) ->
        {:error, :candidate_check_snapshot_missing}

      true ->
        :ok
    end
  end

  defp result(packet) do
    %{
      "candidate_id" => packet["candidate_id"],
      "revision_id" => packet["result_revision_id"],
      "report_ids" => packet["report_ids"] || [],
      "check_set_fingerprint" => packet["check_set_fingerprint"],
      "run_check_set_fingerprint" => packet["run_check_set_fingerprint"]
    }
  end

  defp same_principal?(%Principal{} = left, %Principal{} = right),
    do: Principal.to_map(left) == Principal.to_map(right)
end
