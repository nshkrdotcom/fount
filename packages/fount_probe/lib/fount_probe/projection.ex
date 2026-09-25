defmodule FountProbe.Projection do
  @moduledoc "Exact fragments, legal reading cutoffs and access-limited states. No future or hidden text is smuggled into a state."
  alias Fount.{Query, Writing.UTF8Span}

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

  def select(model, selection, opts \\ []) do
    with {:ok, selected} <- selected_ids(model, selection) do
      omitted = MapSet.new(for s <- model.ir.scenes, s.omitted?, id <- s.element_ids, do: id)

      units =
        model.ir.elements
        |> Enum.with_index()
        |> Enum.flat_map(fn {e, n} ->
          included =
            MapSet.member?(selected, e.id) and
              (Keyword.get(opts, :include_omitted, false) or not MapSet.member?(omitted, e.id))

          kind_ok =
            e.type in @performed or (e.type == :note and Keyword.get(opts, :include_notes, false)) or
              (e.type == :boneyard and Keyword.get(opts, :include_boneyards, false))

          if included and kind_ok,
            do: clip_selection(fragments(model, e, n, opts), selection, e, model),
            else: []
        end)

      {:ok, units}
    end
  end

  defp clip_selection(units, %{"targets" => targets}, element, model) do
    exact = Enum.filter(targets, &(&1["kind"] == "element" and &1["id"] == element.id))

    broader =
      Enum.any?(targets, fn target ->
        if target["kind"] == "element" do
          false
        else
          case target_ids(model, target) do
            {:ok, ids} -> element.id in ids
            _ -> false
          end
        end
      end)

    if broader or Enum.any?(exact, &is_nil(&1["span"])) do
      units
    else
      for unit <- units,
          target <- exact,
          first = max(unit["target"]["span"]["byte_start"], target["span"]["byte_start"]),
          last = min(unit["target"]["span"]["byte_end"], target["span"]["byte_end"]),
          first < last do
        {:ok, text} = UTF8Span.extract(element.text, {first, last})
        span = %{"byte_start" => first, "byte_end" => last}

        unit
        |> Map.put("text", Fount.Fountain.Inline.plain(text))
        |> Map.put("excerpt", text)
        |> Map.put("target", Map.put(unit["target"], "span", span))
        |> Map.put("evidence_id", unit["revision_id"] <> ":" <> element.id <> ":#{first}-#{last}")
      end
      |> Enum.uniq_by(& &1["evidence_id"])
    end
  end

  defp clip_selection(units, _, _, _), do: units

  def selected_ids(model, %{"whole_screenplay" => true}),
    do: {:ok, MapSet.new(model.ir.elements, & &1.id)}

  def selected_ids(model, %{"targets" => targets}) when is_list(targets) and targets != [] do
    Enum.reduce_while(targets, {:ok, MapSet.new()}, fn t, {:ok, ids} ->
      case target_ids(model, t) do
        {:ok, found} -> {:cont, {:ok, Enum.reduce(found, ids, &MapSet.put(&2, &1))}}
        error -> {:halt, error}
      end
    end)
  end

  def selected_ids(_, _), do: {:error, :invalid_selection}

  def target_ids(model, target) do
    case Fount.Target.resolve(model, target) do
      {:ok, %Fount.Screenplay{}} ->
        {:ok, Enum.map(model.ir.elements, & &1.id)}

      {:ok, %Fount.IR.Scene{} = s} ->
        {:ok, s.element_ids}

      {:ok, %Fount.IR.DialogueBlock{} = b} ->
        {:ok, [b.cue_id | b.body_ids]}

      {:ok, %Fount.IR.Element{} = e} ->
        case target["span"] do
          nil -> {:ok, [e.id]}
          span -> with {:ok, _} <- UTF8Span.extract(e.text, span), do: {:ok, [e.id]}
        end

      {:ok, %Fount.Cast.Character{} = c} ->
        {:ok,
         Enum.uniq(
           Enum.flat_map(Query.character_dialogue(model, c.id), &[&1.cue_id | &1.body_ids]) ++
             Enum.map(Query.character_mentions(model, c.id), & &1.element_id)
         )}

      {:ok, _} ->
        {:error, :nontext_selection}

      error ->
        error
    end
  end

  @doc "Entry plus complete action/dialogue groups. Dual partners have one joint cutoff."
  def points(model, scene_id) do
    with {:ok, elements} <- Query.scene_elements(model, scene_id) do
      ids = Enum.map(elements, & &1.id)

      endings =
        Enum.flat_map(elements, fn e ->
          b = Query.block_for(model, e.id)

          cond do
            e.type == :scene_heading ->
              []

            b && b.dual_with ->
              partner = Query.dialogue_block(model, b.dual_with)

              last =
                ([b.cue_id | b.body_ids] ++ [partner.cue_id | partner.body_ids])
                |> Enum.max_by(fn candidate -> Enum.find_index(ids, &(&1 == candidate)) end)

              if e.id == last, do: [last], else: []

            b ->
              if e.id == List.last(b.body_ids), do: [e.id], else: []

            e.type in @performed ->
              [e.id]

            true ->
              []
          end
        end)

      {:ok, Enum.map([nil | endings], &%{"scene_id" => scene_id, "through_element_id" => &1})}
    end
  end

  def at(model, point, projection, opts \\ []) do
    with {:ok, cut} <- cutoff(model, point),
         {:ok, all} <- select(model, %{"whole_screenplay" => true}) do
      prior =
        if Keyword.get(opts, :include_prior_context, true),
          do: all,
          else: Enum.filter(all, &(&1["scene_id"] == point["scene_id"]))

      visible = Enum.filter(prior, &(&1["ordinal"] <= cut))

      case projection do
        "page_reader" ->
          state(model, point, visible, projection, %{"complete_context" => true})

        "audience_estimate" ->
          # Cues may disclose identities unavailable to a viewer. Keep linkage opaque.
          neutral = neutral_cues(visible, model)

          state(model, point, neutral, projection, %{
            "complete_context" => false,
            "projection_gaps" => [
              "Cue identities are neutralized. Interior prose remains a page-based estimate unless observable units are supplied."
            ]
          })

        "character_access" ->
          character_state(model, point, visible, cut, opts)

        _ ->
          {:error, :invalid_projection}
      end
    end
  end

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
        Enum.find(candidates, fn candidate ->
          case cutoff(model, candidate) do
            {:ok, n} -> n >= ordinal
            _ -> false
          end
        end)

      if point, do: {:ok, point}, else: {:error, :no_complete_observation_point}
    else
      _ -> {:error, :unknown_observation_target}
    end
  end

  def resolve_point(_, _), do: {:error, :invalid_observation_target}

  def evidence(units),
    do:
      Enum.map(
        units,
        &Map.take(&1, ~w(evidence_id screenplay_id revision_id target excerpt role))
      )

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

    {:ok, value, evidence(units)}
  end

  defp character_state(model, point, visible, cut, opts) do
    id = Keyword.get(opts, :character_id)

    if not Map.has_key?(model.cast, id) do
      {:error, :unknown_character}
    else
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

      {accepted, excluded} =
        Enum.split_with(declared ++ inferred, fn entry ->
          entry["access"] == "writer_declared" or
            (entry["access"] == "text_supported" and is_number(entry["support_probability"]) and
               entry["support_probability"] >= Map.get(entry, "access_support_threshold", 0.8) and
               is_number(entry["confidence"]) and
               entry["confidence"] >= Map.get(entry, "access_confidence_threshold", 0.7))
        end)

      units =
        Enum.flat_map(accepted, fn entry ->
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
                "text" => Fount.Fountain.Inline.plain(entry["excerpt"]),
                "type" => to_string(element.type),
                "role" => "input_context",
                "channel" => entry["channel"],
                "access" => entry["access"]
              }
            ]
          else
            []
          end
        end)

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

  defp fragments(model, e, ordinal, opts) do
    hidden =
      if e.type in [:note, :boneyard] and
           (Keyword.get(opts, :include_notes, false) or
              Keyword.get(opts, :include_boneyards, false)),
         do: [],
         else: Regex.scan(~r/\[\[.*?\]\]|\/\*.*?\*\//s, e.text, return: :index) |> Enum.map(&hd/1)

    {segments, cursor} =
      Enum.reduce(hidden, {[], 0}, fn {first, size}, {acc, cursor} ->
        {if(first > cursor, do: acc ++ [{cursor, first}], else: acc), first + size}
      end)

    segments =
      if cursor < byte_size(e.text), do: segments ++ [{cursor, byte_size(e.text)}], else: segments

    scene = Query.scene_for(model, e.id)

    for {first, last} <- segments,
        last > first,
        excerpt = binary_part(e.text, first, last - first),
        String.trim(excerpt) != "" do
      %{
        "evidence_id" => "ev_" <> model.revision.id <> "_" <> e.id <> "_#{first}_#{last}",
        "screenplay_id" => model.id,
        "revision_id" => model.revision.id,
        "target" => %{
          "kind" => "element",
          "id" => e.id,
          "span" => %{"byte_start" => first, "byte_end" => last}
        },
        "excerpt" => excerpt,
        "text" => Fount.Fountain.Inline.plain(excerpt),
        "type" => to_string(e.type),
        "scene_id" => scene && scene.id,
        "ordinal" => ordinal,
        "role" => "input_context"
      }
    end
  end
end
