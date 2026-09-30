defmodule FountRun.AnalysisLineage do
  @moduledoc false

  @doc "Returns the safe analysis lineage already persisted with a Workshop session."
  def from_session(session) when is_map(session) do
    packet =
      get_in(session, ["progress", "preparation", "context", "data", "writer_intelligence"])

    compact(%{
      "writer" => packet_summary(packet)
    })
  end

  def from_session(_), do: %{}

  @doc "Returns safe pre-analysis and revision-analysis identifiers from a persisted candidate."
  def from_candidate(candidate) when is_map(candidate) do
    compact(%{
      "writer" =>
        candidate
        |> get_in(["provenance", "intelligence_lineage", "pre_analysis_packet"])
        |> packet_summary(),
      "revision" =>
        candidate
        |> get_in(["provenance", "revision_intelligence"])
        |> packet_summary()
    })
  end

  def from_candidate(_), do: %{}

  @doc "Combines candidate analysis summaries without copying evidence or semantic payloads."
  def from_candidates(candidates) when is_list(candidates) do
    Enum.reduce(candidates, %{}, fn candidate, acc -> merge(acc, from_candidate(candidate)) end)
  end

  def from_candidates(_), do: %{}

  @doc "Merges lineage summaries, preferring the right-hand non-nil packet for each phase."
  def merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, old, new -> new || old end)
  end

  @doc "Projects safe per-step analysis lineage from stored Run stage results."
  def progress(steps) when is_list(steps) do
    steps
    |> Enum.flat_map(fn step ->
      result = step["result"] || %{}
      analysis = result["analysis"] || %{}

      if is_map(analysis) and map_size(analysis) > 0 do
        [
          compact(%{
            "step_id" => step["id"],
            "stage" => step["stage"],
            "iteration" => step["iteration"],
            "session_id" => result["session_id"] || step["session_id"],
            "candidate_id" => result["candidate_id"] || step["output_candidate_id"],
            "revision_id" => result["revision_id"] || step["output_revision_id"],
            "writer" => analysis["writer"],
            "revision" => analysis["revision"]
          })
        ]
      else
        []
      end
    end)
  end

  def progress(_), do: []

  defp packet_summary(packet) when is_map(packet) do
    compact(%{
      "packet_id" => packet["id"],
      "analysis_run_id" => get_in(packet, ["provenance", "analysis_run_id"]),
      "status" => packet["status"],
      "playbook" => packet["playbook"],
      "source_revision_id" => packet["source_revision"],
      "reason" => packet["reason"],
      "resources" => resource_summary(packet["resource_usage"])
    })
  end

  defp packet_summary(_), do: nil

  defp resource_summary(%{"capability_runs" => runs}) when is_list(runs) do
    totals =
      Enum.reduce(runs, %{}, fn run, acc ->
        actual = run["actual"] || %{}

        acc
        |> add_known("scheduled_states", actual["scheduled_states"])
        |> add_known("successful_states", actual["successful_states"])
        |> add_known("cache_hits", actual["cache_hits"])
        |> add_known("provider_requests", actual["provider_requests"])
      end)

    if map_size(totals) == 0, do: nil, else: totals
  end

  defp resource_summary(_), do: nil

  defp add_known(acc, _key, nil), do: acc

  defp add_known(acc, key, value) when is_integer(value),
    do: Map.update(acc, key, value, &(&1 + value))

  defp add_known(acc, _key, _value), do: acc

  defp compact(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
