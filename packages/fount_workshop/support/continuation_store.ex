defmodule FountWorkshop.TestSupport.ContinuationStore do
  @moduledoc false
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
      saved =
        candidate
        |> Map.put("session_id", session_id)
        |> Map.put("screenplay_id", candidate["screenplay"].id)

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
