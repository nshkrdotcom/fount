defmodule Fount.Intelligence.StoryWorld.Renderer do
  @moduledoc "Deterministic JSON and Markdown StoryWorld reference rendering for writer/domain review."

  alias Fount.Intelligence.StoryWorld.Inspection
  alias Fount.Screenplay.Model
  alias Fount.Writing.CanonicalJSON

  def json(world, opts \\ []) do
    world
    |> Inspection.packet(opts)
    |> CanonicalJSON.encode!()
  end

  def markdown(world, opts \\ []) do
    packet = Inspection.packet(world, opts)
    reference = packet["reference"]

    [
      "# Story World Reference\n\n",
      "Source revision: `",
      packet["source_revision"],
      "`\n\n",
      "## Writer question\n\n",
      packet["question"],
      "\n\n",
      "## What this reference contains\n\n",
      summary_table(packet["summary"]),
      "\n## Narrative scopes\n\n",
      render_collection(reference, "scopes", &scope_line/1),
      "\n## Events\n\n",
      render_collection(reference, "events", &event_line/1),
      "\n## Assertions and facts\n\n",
      render_collection(reference, "assertions", &assertion_line/1),
      "\n## State changes\n\n",
      render_collection(reference, "state_transitions", &transition_line/1),
      "\n## Story-time constraints\n\n",
      render_collection(reference, "story_time_constraints", &constraint_line/1),
      "\n## Causal relations\n\n",
      render_collection(reference, "causal_relations", &causal_line/1),
      "\n## Conflicts\n\n",
      render_collection(reference, "conflicts", &conflict_line/1),
      "\n## Evidence\n\n",
      render_evidence(packet["evidence"]),
      "\n## Uncertainty retained\n\n",
      render_uncertainty(packet["uncertainty"]),
      "\n## Limitations\n\n",
      bullets(packet["limitations"])
    ]
    |> :erlang.iolist_to_binary()
  end

  defp summary_table(summary) do
    summary
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {key, value} -> "- #{humanize(key)}: #{value}\n" end)
  end

  defp render_collection(reference, key, formatter) when is_map(reference) do
    case Map.get(reference, key, []) do
      [] -> "_None recorded._\n"
      items -> items |> Enum.map(formatter) |> Enum.map(&["- ", &1, "\n"])
    end
  end

  defp render_collection(_reference, _key, _formatter),
    do: "_Focused packet; see JSON for selected values._\n"

  defp scope_line(item), do: "`#{item["id"]}` — #{item["kind"]}#{parent_suffix(item)}"

  defp event_line(item) do
    label = item["label"] || item["kind"]
    "`#{item["id"]}` — #{label} (scope `#{item["scope_id"]}`)"
  end

  defp assertion_line(item) do
    "`#{item["id"]}` — #{compact(item["subject"])} #{item["predicate"]} #{compact(item["object"])} (#{item["stance"] || "asserted"})"
  end

  defp transition_line(item) do
    "`#{item["id"]}` — #{compact(item["subject"])}.#{item["attribute"]}: #{compact(item["from"])} -> #{compact(item["to"])} at `#{item["event_id"]}`"
  end

  defp constraint_line(item) do
    "`#{item["id"]}` — `#{item["left"]}` -> `#{item["right"]}`: #{Enum.join(item["relations"] || [], " | ")}"
  end

  defp causal_line(item),
    do: "`#{item["id"]}` — `#{item["from"]}` #{item["type"]} `#{item["to"]}`"

  defp conflict_line(item), do: "**#{item["kind"]}** — #{item["message"]} (`#{item["id"]}`)"

  defp render_evidence([]), do: "_No evidence in this packet._\n"

  defp render_evidence(evidence) do
    evidence
    |> Enum.sort_by(& &1["id"])
    |> Enum.map(fn item ->
      target = item["target"] || %{}
      excerpt = item["excerpt"] || ""
      "- `#{item["id"]}` — #{target["kind"]}:`#{target["id"]}` — #{inspect(excerpt)}\n"
    end)
  end

  defp render_uncertainty(uncertainty) do
    [
      "- Unknown story-time pairs: ",
      Integer.to_string(length(uncertainty["unknown_story_time_pairs"] || [])),
      "\n",
      "- Ambiguous direct story-time relations: ",
      Integer.to_string(length(uncertainty["ambiguous_story_time"] || [])),
      "\n",
      "- Contradictory direct story-time relations: ",
      Integer.to_string(length(uncertainty["contradictory_story_time"] || [])),
      "\n",
      "- Competing assertion groups: ",
      Integer.to_string(length(uncertainty["competing_assertions"] || [])),
      "\n"
    ]
  end

  defp bullets(items), do: Enum.map(items, &["- ", &1, "\n"])
  defp humanize(value), do: value |> String.replace("_", " ")
  defp parent_suffix(%{"parent_id" => nil}), do: ""
  defp parent_suffix(%{"parent_id" => parent}), do: " (parent `#{parent}`)"
  defp parent_suffix(_), do: ""

  defp compact(value) do
    value
    |> Model.plain()
    |> Jason.encode!()
  end
end
