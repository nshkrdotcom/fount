defmodule Fount.Intelligence.Capabilities.Support do
  @moduledoc false

  alias Fount.Intelligence.StoryWorld
  alias Fount.Screenplay.Model
  alias Fount.Writing.CanonicalJSON

  @relationship_prefix "relationship."

  def answer(entry, key) when is_map(entry), do: get_in(entry, ["answers", to_string(key)])
  def answer(_, _), do: nil

  def status(entry, key) do
    case answer(entry, key) do
      %{"status" => status} when is_binary(status) -> status
      _ -> "unavailable"
    end
  end

  def supported?(entry, key), do: status(entry, key) == "supported"
  def not_supported?(entry, key), do: status(entry, key) == "not_supported"

  def choice(entry, key) do
    case answer(entry, key) do
      %{"status" => "supported", "choice" => choice} when is_binary(choice) -> choice
      _ -> nil
    end
  end

  def measurement_scenes(entries) do
    entries
    |> Enum.map(& &1["scene_id"])
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  def measurement_trajectory(entries, keys) do
    Enum.map(entries, fn entry ->
      %{
        "scene_id" => entry["scene_id"],
        "status" => entry["status"],
        "answers" => Map.new(keys, &{to_string(&1), answer(entry, &1)})
      }
    end)
  end

  def measurement_evidence(entries) do
    entries
    |> Enum.flat_map(fn entry ->
      Enum.flat_map(entry["observations"] || [], fn observation ->
        observation["evidence"] || []
      end)
    end)
    |> uniq_plain_evidence()
  end

  def evidence(objects) do
    objects
    |> List.wrap()
    |> Enum.flat_map(fn object -> Map.get(object, :evidence, []) end)
    |> Enum.map(&Model.plain/1)
    |> uniq_plain_evidence()
  end

  def merge_evidence(groups) do
    groups
    |> Enum.flat_map(&List.wrap/1)
    |> uniq_plain_evidence()
  end

  def event_id_for_scene(scene_id) when is_binary(scene_id), do: "scene:" <> scene_id
  def event_id_for_scene(_), do: nil

  def event_presentation_key(world, event_id) do
    case world.events[event_id] do
      %{presentation_points: [point | _]} ->
        {point.scene_ordinal || 1_000_000, point.element_ordinal || 1_000_000, event_id}

      _ ->
        {1_000_000, 1_000_000, to_string(event_id)}
    end
  end

  def transition_presentation_key(world, transition),
    do: event_presentation_key(world, transition.event_id)

  def story_order_links(world, objects, event_id_fun) do
    ordered = Enum.sort_by(objects, &event_presentation_key(world, event_id_fun.(&1)))

    links =
      ordered
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [left, right] ->
        left_event = event_id_fun.(left)
        right_event = event_id_fun.(right)
        relation = StoryWorld.story_time_relation(world, left_event, right_event)

        %{
          "left_id" => left.id,
          "right_id" => right.id,
          "left_event_id" => left_event,
          "right_event_id" => right_event,
          "story_time_relation" => Model.plain(relation),
          "presentation_conflicts_with_known_story_time" => reverse_relation?(relation)
        }
      end)

    %{
      "presentation_order" => Enum.map(ordered, & &1.id),
      "adjacent_story_time_relations" => links,
      "non_linear_presentation" => Enum.any?(links, & &1["presentation_conflicts_with_known_story_time"])
    }
  end

  def causal_edges(world), do: world.causal.edges |> Map.values() |> Enum.sort_by(& &1.id)

  def outgoing_edges(world, ids) do
    ids = MapSet.new(List.wrap(ids))
    Enum.filter(causal_edges(world), &MapSet.member?(ids, &1.from))
  end

  def incoming_edges(world, ids) do
    ids = MapSet.new(List.wrap(ids))
    Enum.filter(causal_edges(world), &MapSet.member?(ids, &1.to))
  end

  def alternate_support(world) do
    world
    |> causal_edges()
    |> Enum.group_by(& &1.to)
    |> Enum.flat_map(fn {target, edges} ->
      sources = edges |> Enum.map(& &1.from) |> Enum.uniq() |> Enum.sort()

      if length(sources) > 1,
        do: [%{"target" => target, "sources" => sources, "edge_ids" => Enum.map(edges, & &1.id) |> Enum.sort()}],
        else: []
    end)
    |> Enum.sort_by(& &1["target"])
  end

  def causal_reach(world, id) do
    descendants = StoryWorld.causal_descendants(world, id)
    %{"id" => id, "descendant_ids" => descendants, "descendant_count" => length(descendants)}
  end

  def relationship_transition?(%{attribute: attribute}) when is_binary(attribute),
    do: String.starts_with?(attribute, @relationship_prefix)

  def relationship_transition?(_), do: false

  def subject_equal?(left, right), do: value_key(left) == value_key(right)

  def character_in_value?(value, character) do
    cond do
      subject_equal?(value, character) -> true
      is_list(value) -> Enum.any?(value, &character_in_value?(&1, character))
      is_map(value) -> Enum.any?(Map.values(value), &character_in_value?(&1, character))
      true -> false
    end
  end

  def relationship_subject?(subject, pair) when is_list(pair) and length(pair) >= 2 do
    pair = Enum.take(pair, 2)

    cond do
      is_map(subject) ->
        values = [subject["from"] || subject[:from], subject["to"] || subject[:to]]
        same_members?(values, pair)

      is_list(subject) ->
        same_members?(subject, pair)

      true ->
        false
    end
  end

  def relationship_subject?(_, _), do: false

  def interaction_has_pair?(%{participants: participants}, pair),
    do: Enum.all?(Enum.take(pair, 2), &character_in_value?(participants, &1))

  def interaction_has_pair?(_, _), do: false

  def event_has_character?(%{participants: participants}, character),
    do: character_in_value?(participants, character)

  def event_has_character?(_, _), do: false

  def active_at?(active_at, event_id) when is_list(active_at), do: event_id in active_at
  def active_at?(active_at, event_id), do: active_at == event_id

  def plain_objects(objects), do: objects |> Enum.map(&Model.plain/1) |> Enum.sort_by(& &1["id"])

  def diagnosis(id, concern, hypothesis, support, opts \\ []) do
    %{
      "id" => id,
      "concern" => concern,
      "hypothesis" => hypothesis,
      "support" => Enum.uniq(List.wrap(support)) |> Enum.sort(),
      "counterevidence" => Keyword.get(opts, :counterevidence, []) |> Enum.uniq() |> Enum.sort(),
      "uncertainty" => Keyword.get(opts, :uncertainty, "medium"),
      "claim_class" => "model_estimated_interpretation",
      "limitations" => List.wrap(Keyword.get(opts, :limitations, []))
    }
  end

  def source_ids(objects), do: objects |> Enum.map(& &1.id) |> Enum.uniq() |> Enum.sort()

  def statuses(entries, key), do: Enum.map(entries, &status(&1, key))

  def any_supported?(entries, key), do: Enum.any?(entries, &supported?(&1, key))
  def all_not_supported?([], _key), do: false
  def all_not_supported?(entries, key), do: Enum.all?(entries, &not_supported?(&1, key))

  def relevant_entries(entries, scene_id) when is_binary(scene_id),
    do: Enum.filter(entries, &(&1["scene_id"] == scene_id))

  def relevant_entries(entries, _), do: entries

  defp reverse_relation?(%{status: :known, relations: relations}), do: "after" in relations
  defp reverse_relation?(%{"status" => "known", "relations" => relations}), do: "after" in relations
  defp reverse_relation?(_), do: false

  defp same_members?(left, right) do
    left = Enum.reject(left, &is_nil/1)
    length(left) == length(right) and MapSet.new(Enum.map(left, &value_key/1)) == MapSet.new(Enum.map(right, &value_key/1))
  end

  defp value_key(value), do: CanonicalJSON.hash(Model.plain(value))

  defp uniq_plain_evidence(evidence) do
    evidence
    |> Enum.filter(&is_map/1)
    |> Enum.uniq_by(fn item -> item["id"] || item["evidence_id"] || CanonicalJSON.hash(item) end)
    |> Enum.sort_by(fn item -> item["id"] || item["evidence_id"] || CanonicalJSON.hash(item) end)
  end
end
