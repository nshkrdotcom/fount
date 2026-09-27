defmodule Fount.Observe.Projection do
  @moduledoc "Presentation-order, audience and character-access measurement projections. Future and hidden material stay excluded."
  alias Fount.Fountain.Inline
  alias Fount.Query
  alias Fount.Writing.UTF8Span

  @performed [
    :scene_heading,
    :action,
    :character,
    :dialogue,
    :parenthetical,
    :transition,
    :centered,
    :lyric
  ]

  @doc "Entry plus complete action/dialogue groups. Dual partners have one joint cutoff."
  def points(model, scene_id) do
    with {:ok, elements} <- Query.scene_elements(model, scene_id) do
      ids = Enum.map(elements, & &1.id)

      endings = Enum.flat_map(elements, &point_ending(&1, model, ids))

      {:ok, Enum.map([nil | endings], &%{"scene_id" => scene_id, "through_element_id" => &1})}
    end
  end

  defp point_ending(element, model, ids) do
    block = Query.block_for(model, element.id)

    cond do
      element.type == :scene_heading -> []
      block && block.dual_with -> dual_ending(element, block, model, ids)
      block -> if element.id == List.last(block.body_ids), do: [element.id], else: []
      element.type in @performed -> [element.id]
      true -> []
    end
  end

  defp dual_ending(element, block, model, ids) do
    partner = Query.dialogue_block(model, block.dual_with)

    last =
      ([block.cue_id | block.body_ids] ++ [partner.cue_id | partner.body_ids])
      |> Enum.max_by(fn candidate -> Enum.find_index(ids, &(&1 == candidate)) end)

    if element.id == last, do: [last], else: []
  end

  def at(model, point, projection, opts \\ []) do
    with {:ok, cut} <- cutoff(model, point),
         {:ok, all} <- Fount.Selection.select(model, %{"whole_screenplay" => true}) do
      prior =
        if Keyword.get(opts, :include_prior_context, true),
          do: all,
          else: Enum.filter(all, &(&1["scene_id"] == point["scene_id"]))

      visible = Enum.filter(prior, &(&1["ordinal"] <= cut))

      case projection do
        "page_reader" ->
          state(model, point, visible, projection, %{"complete_context" => true})

        "audience_estimate" ->
          # Page directions can include interior knowledge. Admit visual beats only when
          # an exact fragment has been explicitly classified as observable.
          observable = MapSet.new(Keyword.get(opts, :observable_evidence_ids) || [])

          audience = Enum.filter(visible, &audience_unit?(&1, observable))

          neutral = neutral_cues(audience, model)

          state(model, point, neutral, projection, %{
            "complete_context" => false,
            "projection_gaps" => [
              "Only dialogue and explicitly observable action fragments are included. Visual access, speaker identity and off-screen hearing remain uncertain."
            ]
          })

        "character_access" ->
          character_state(model, point, visible, cut, opts)

        _ ->
          {:error, :invalid_projection}
      end
    end
  end

  defp audience_unit?(unit, observable),
    do:
      unit["type"] in ~w(character dialogue lyric) or
        (unit["type"] == "action" and MapSet.member?(observable, unit["evidence_id"]))

  def cutoff(model, %{"scene_id" => scene_id, "through_element_id" => through}) do
    with {:ok, points} <- points(model, scene_id) do
      if Enum.any?(points, &(&1["through_element_id"] == through)) do
        id = through || Query.scene(model, scene_id).heading_id
        index = Enum.find_index(model.ir.elements, &(&1.id == id))
        {:ok, if(is_nil(through), do: index - 1, else: index)}
      else
        {:error, :illegal_or_split_cutoff}
      end
    end
  end

  def cutoff(_, _), do: {:error, :invalid_point}

  @doc "Resolves a typed observation target to a legal complete action or dialogue cutoff."
  def resolve_point(model, %{"scene_id" => _, "through_element_id" => _} = point) do
    with {:ok, _} <- cutoff(model, point), do: {:ok, point}
  end

  def resolve_point(model, %{"kind" => "scene", "id" => id}) do
    with {:ok, points} <- points(model, id), do: {:ok, List.last(points)}
  end

  def resolve_point(model, %{"kind" => "screenplay", "id" => id}) when id == model.id do
    case List.last(model.ir.scenes) do
      nil -> {:error, :empty_screenplay}
      scene -> resolve_point(model, %{"kind" => "scene", "id" => scene.id})
    end
  end

  def resolve_point(model, %{"kind" => kind, "id" => id})
      when kind in ["element", "dialogue_block"] do
    element_id =
      if kind == "dialogue_block" do
        case Query.dialogue_block(model, id) do
          nil -> nil
          block -> List.last(block.body_ids) || block.cue_id
        end
      else
        id
      end

    with scene when not is_nil(scene) <- Query.scene_for(model, element_id),
         {:ok, candidates} <- points(model, scene.id),
         ordinal when is_integer(ordinal) <-
           Enum.find_index(model.ir.elements, &(&1.id == element_id)) do
      # If the target is inside a turn, use its complete turn (or joint dual turn).
      point =
        Enum.find(candidates, &cutoff_at_or_after?(&1, model, ordinal))

      if point, do: {:ok, point}, else: {:error, :no_complete_observation_point}
    else
      _ -> {:error, :unknown_observation_target}
    end
  end

  def resolve_point(_, _), do: {:error, :invalid_observation_target}

  defp cutoff_at_or_after?(candidate, model, ordinal) do
    case cutoff(model, candidate) do
      {:ok, index} -> index >= ordinal
      _ -> false
    end
  end

  def compact(units),
    do: Enum.map(units, &Map.take(&1, ~w(evidence_id type text speaker channel access)))

  defp state(model, point, units, projection, extras) do
    value =
      Map.merge(
        %{
          "screenplay_id" => model.id,
          "revision_id" => model.revision.id,
          "point" => point,
          "projection" => projection,
          "material" => compact(units)
        },
        extras
      )

    {:ok, value, Fount.Selection.evidence(units)}
  end

  defp character_state(model, point, visible, cut, opts) do
    id = Keyword.get(opts, :character_id)

    if Map.has_key?(model.cast, id) do
      character_state_known(model, point, visible, cut, opts, id)
    else
      {:error, :unknown_character}
    end
  end

  defp character_state_known(model, point, visible, cut, opts, id) do
    own = MapSet.new(Enum.flat_map(Query.character_dialogue(model, id), & &1.body_ids))

    behavior =
      visible
      |> Enum.filter(&MapSet.member?(own, &1["target"]["id"]))
      |> Enum.map(
        &Map.merge(&1, %{"channel" => "utterance", "access" => "own_behavior_not_fact"})
      )

    declared =
      model.authored_items
      |> Map.values()
      |> Enum.filter(
        &(&1["kind"] == "perspective_access" and &1["status"] == "active" and
            &1["value"]["character_id"] == id)
      )
      |> Enum.flat_map(&List.wrap(&1["value"]["entries"]))

    inferred =
      if Keyword.get(opts, :access_mode, "evidence") == "writer_declared",
        do: [],
        else: Keyword.get(opts, :access_ledger, []) |> Enum.filter(&(&1["character_id"] == id))

    {accepted, excluded} = Enum.split_with(declared ++ inferred, &accepted_access?/1)

    units = Enum.flat_map(accepted, &access_unit(&1, model, cut))

    combined = Enum.uniq_by(units ++ behavior, & &1["evidence_id"])

    state(model, point, combined, "character_access", %{
      "character_id" => id,
      "complete_context" => false,
      "access_coverage" => %{
        "accepted_units" => length(units),
        "unresolved_units" => length(excluded),
        "own_utterances" => length(behavior)
      },
      "projection_gaps" => [
        "Presence does not establish access; unestablished access is excluded."
      ]
    })
  end

  defp accepted_access?(entry) do
    entry["access"] == "writer_declared" or
      (entry["access"] == "text_supported" and is_number(entry["support_probability"]) and
         entry["support_probability"] >= Map.get(entry, "access_support_threshold", 0.8) and
         is_number(entry["confidence"]) and
         entry["confidence"] >= Map.get(entry, "access_confidence_threshold", 0.7))
  end

  defp access_unit(entry, model, cut) do
    target = entry["target"]
    element = if is_map(target), do: Query.node(model, target["id"])
    ordinal = if element, do: Enum.find_index(model.ir.elements, &(&1.id == element.id))
    as_of = entry["as_of"]
    time_ok = if as_of, do: match?({:ok, n} when n <= cut, cutoff(model, as_of)), else: true

    if element && ordinal <= cut && time_ok &&
         entry["revision_id"] in [nil, model.revision.id] &&
         UTF8Span.verify(element.text, target["span"], entry["excerpt"]) == :ok do
      [
        %{
          "evidence_id" => "access_" <> Fount.ID.hash(Jason.encode!(target)),
          "screenplay_id" => model.id,
          "revision_id" => model.revision.id,
          "target" => target,
          "excerpt" => entry["excerpt"],
          "text" => Inline.plain(entry["excerpt"]),
          "type" => to_string(element.type),
          "role" => "input_context",
          "channel" => entry["channel"],
          "access" => entry["access"]
        }
      ]
    else
      []
    end
  end

  defp neutral_cues(units, model) do
    cues =
      model.ir.elements
      |> Enum.filter(&(&1.type == :character))
      |> Enum.map(& &1.text)
      |> Enum.uniq()
      |> Enum.with_index(1)
      |> Map.new(fn {name, n} -> {name, "speaker_#{n}"} end)

    Enum.map(units, fn u ->
      if u["type"] == "character",
        do: Map.put(u, "text", cues[u["excerpt"]] || "speaker"),
        else: u
    end)
  end
end
