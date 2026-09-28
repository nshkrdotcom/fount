defmodule FountWorkshop.TestSupport.ContinuationStore do
  @moduledoc false
  alias Fount.Writing.{Approval, Authority, CheckSet, ReviewGate}
  def start_link(model),
    do:
      Agent.start_link(fn ->
        %{
          models: %{model.revision.id => model},
          head: model,
          sessions: %{},
          candidates: %{},
          reports: %{}
        }
      end)

  def head(agent), do: Agent.get(agent, & &1.head)

  def load_revision(agent, sid, rid) do
    Agent.get(agent, fn state ->
      case state.models[rid] do
        %{id: ^sid} = model -> {:ok, model}
        _ -> {:error, :not_found}
      end
    end)
  end

  def save_session(agent, session) do
    Agent.get_and_update(agent, &save_session_state(&1, session))
  end

  defp save_session_state(state, session) do
    previous = state.sessions[session["id"]]

    if previous && previous["lock_version"] != session["lock_version"] do
      {{:error, :stale_session}, state}
    else
      saved =
        Map.put(session, "lock_version", if(previous, do: previous["lock_version"] + 1, else: 1))

      {{:ok, saved}, put_in(state, [:sessions, saved["id"]], saved)}
    end
  end

  def session(agent, id),
    do:
      Agent.get(agent, fn state ->
        if state.sessions[id], do: {:ok, state.sessions[id]}, else: {:error, :not_found}
      end)

  def save_candidate(agent, session_id, candidate) do
    Agent.get_and_update(agent, fn state ->
      session = state.sessions[session_id] || %{"request" => %{}}
      {:ok, snapshot} = CheckSet.snapshot(session, candidate["provenance"] || %{})

      saved =
        candidate
        |> Map.put("session_id", session_id)
        |> Map.put("screenplay_id", candidate["screenplay"].id)
        |> Map.put("required_checks", snapshot["required_checks"])
        |> Map.put("check_set_fingerprint", snapshot["check_set_fingerprint"])
        |> Map.put_new("decision", "proposed")
        |> Map.put_new("decision_actor", nil)

      next =
        state
        |> put_in([:candidates, saved["id"]], saved)
        |> put_in([:models, saved["screenplay"].revision.id], saved["screenplay"])

      {{:ok, saved}, next}
    end)
  end

  def candidate(agent, id),
    do:
      Agent.get(agent, fn state ->
        if state.candidates[id], do: {:ok, state.candidates[id]}, else: {:error, :not_found}
      end)

  def candidates_for_session(agent, id),
    do:
      Agent.get(agent, &Enum.filter(Map.values(&1.candidates), fn c -> c["session_id"] == id end))

  def accept_candidate(agent, id, opts) do
    Agent.get_and_update(agent, fn state ->
      candidate = state.candidates[id]
      approval = Keyword.get(opts, :approval)
      authority = Keyword.get(opts, :authority)

      result =
        with %Approval{} <- approval,
             %Authority{} <- authority,
             true <- not is_nil(candidate) or {:error, :not_found},
             :ok <- Authority.authorize(authority, :approve, candidate["screenplay_id"], approval.approver),
             true <- approval.screenplay_id == candidate["screenplay_id"] or {:error, :approval_screenplay_mismatch},
             true <- approval.candidate_id == id or {:error, :approval_candidate_mismatch},
             true <- approval.base_revision_id == candidate["base_revision_id"] or {:error, :approval_base_mismatch},
             true <- approval.content_hash == candidate["screenplay"].revision.content_hash or {:error, :approval_content_mismatch},
             :ok <- fake_review(candidate, approval) do
          {:ok, approval}
        else
          nil -> {:error, :authorized_approval_required}
          false -> {:error, :authorized_approval_required}
          %{} -> {:error, :authorized_approval_required}
          {:error, _} = error -> error
          _ -> {:error, :authorized_approval_required}
        end

      response =
        case result do
          {:error, reason} ->
            {{:error, reason}, state}

          {:ok, approval} ->
            cond do
              candidate["decision"] == "rejected" ->
                {{:error, :already_rejected}, state}

              candidate["decision"] == "accepted" and candidate["approval_id"] == approval.id and
                  candidate["approval_hash"] == Approval.fingerprint(approval) ->
                {{:ok, candidate["screenplay"]}, state}

              candidate["decision"] == "accepted" ->
                {{:error, :acceptance_identity_conflict}, state}

              state.head.revision.id != approval.base_revision_id ->
                {{:error, {:stale_revision, state.head.revision.id}}, state}

              true ->
                accepted =
                  candidate
                  |> Map.put("decision", "accepted")
                  |> Map.put("decision_actor", approval.approver.id)
                  |> Map.put("approval_id", approval.id)
                  |> Map.put("approval_hash", Approval.fingerprint(approval))

                next =
                  state
                  |> put_in([:candidates, id], accepted)
                  |> Map.put(:head, candidate["screenplay"])

                {{:ok, candidate["screenplay"]}, next}
            end
        end

      response
    end)
  end

  defp fake_review(candidate, approval) do
    provenance = candidate["provenance"] || %{}
    checks = provenance["checks"] || []

    ReviewGate.validate(
      %{
        "id" => candidate["id"],
        "base_revision_id" => candidate["base_revision_id"],
        "content_hash" => candidate["screenplay"].revision.content_hash,
        "structural_errors" => [],
        "checks" => checks,
        "required_checks" => candidate["required_checks"] || [],
        "check_set_fingerprint" => candidate["check_set_fingerprint"],
        "report_ids" => provenance["report_ids"] || []
      },
      approval.review,
      approval.approver
    )
  end

  def reject_candidate(agent, id, opts) do
    Agent.get_and_update(agent, fn state ->
      case state.candidates[id] do
        nil ->
          {{:error, :not_found}, state}

        %{"decision" => "accepted"} ->
          {{:error, :already_accepted}, state}

        candidate ->
          rejected =
            candidate
            |> Map.put("decision", "rejected")
            |> Map.put("decision_actor", Keyword.get(opts, :actor))

          {{:ok, rejected}, put_in(state, [:candidates, id], rejected)}
      end
    end)
  end

  def save_report(agent, report, opts) do
    report = FountWorkshop.Store.normalize(report)

    Agent.get_and_update(agent, fn state ->
      models =
        Enum.reduce(opts[:source_models] || [], state.models, &Map.put(&2, &1.revision.id, &1))

      {{:ok, report},
       %{state | models: models, reports: Map.put(state.reports, report["id"], report)}}
    end)
  end

  def report(agent, id),
    do:
      Agent.get(agent, fn state ->
        if state.reports[id], do: {:ok, state.reports[id]}, else: {:error, :not_found}
      end)
end
