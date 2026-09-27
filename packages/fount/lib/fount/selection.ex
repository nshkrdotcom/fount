defmodule Fount.Selection do
  @moduledoc "Exact canonical source selections with UTF-8 byte spans and explicit hidden-material policy."
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

  def select(model, selection, opts \\ []) do
    with {:ok, selected} <- selected_ids(model, selection) do
      omitted = MapSet.new(for s <- model.ir.scenes, s.omitted?, id <- s.element_ids, do: id)

      units =
        Enum.with_index(model.ir.elements)
        |> Enum.flat_map(fn {element, ordinal} ->
          selection_units(model, selection, opts, selected, omitted, element, ordinal)
        end)

      {:ok, units}
    end
  end

  defp selection_units(model, selection, opts, selected, omitted, element, ordinal) do
    included =
      MapSet.member?(selected, element.id) and
        (Keyword.get(opts, :include_omitted, false) or not MapSet.member?(omitted, element.id))

    if included and included_kind?(element, opts),
      do: clip_selection(fragments(model, element, ordinal, opts), selection, element, model),
      else: []
  end

  defp included_kind?(element, opts) do
    element.type in @performed or
      (element.type == :note and Keyword.get(opts, :include_notes, false)) or
      (element.type == :boneyard and Keyword.get(opts, :include_boneyards, false))
  end

  defp clip_selection(units, %{"targets" => targets}, element, model) do
    exact = Enum.filter(targets, &(&1["kind"] == "element" and &1["id"] == element.id))

    broader = Enum.any?(targets, &broader_target?(&1, element, model))

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
        |> Map.put("text", Inline.plain(text))
        |> Map.put("excerpt", text)
        |> Map.put("target", Map.put(unit["target"], "span", span))
        |> Map.put("evidence_id", unit["revision_id"] <> ":" <> element.id <> ":#{first}-#{last}")
      end
      |> Enum.uniq_by(& &1["evidence_id"])
    end
  end

  defp clip_selection(units, _, _, _), do: units

  defp broader_target?(%{"kind" => "element"}, _element, _model), do: false

  defp broader_target?(target, element, model) do
    case target_ids(model, target) do
      {:ok, ids} -> element.id in ids
      _ -> false
    end
  end

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
      {:ok, resolved} -> resolved_target_ids(model, target, resolved)
      error -> error
    end
  end

  defp resolved_target_ids(model, _target, %Fount.Screenplay{}),
    do: {:ok, Enum.map(model.ir.elements, & &1.id)}

  defp resolved_target_ids(_model, _target, %Fount.IR.Scene{} = scene),
    do: {:ok, scene.element_ids}

  defp resolved_target_ids(_model, _target, %Fount.IR.DialogueBlock{} = block),
    do: {:ok, [block.cue_id | block.body_ids]}

  defp resolved_target_ids(_model, target, %Fount.IR.Element{} = element) do
    case target["span"] do
      nil -> {:ok, [element.id]}
      span -> with {:ok, _} <- UTF8Span.extract(element.text, span), do: {:ok, [element.id]}
    end
  end

  defp resolved_target_ids(model, _target, %Fount.Cast.Character{} = character) do
    {:ok,
     Enum.uniq(
       Enum.flat_map(Query.character_dialogue(model, character.id), &[&1.cue_id | &1.body_ids]) ++
         Enum.map(Query.character_mentions(model, character.id), & &1.element_id)
     )}
  end

  defp resolved_target_ids(_, _, _), do: {:error, :nontext_selection}
  def evidence(units),
    do:
      Enum.map(
        units,
        &Map.take(&1, ~w(evidence_id screenplay_id revision_id target excerpt role))
      )

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
        "text" => Inline.plain(excerpt),
        "type" => to_string(e.type),
        "scene_id" => scene && scene.id,
        "ordinal" => ordinal,
        "role" => "input_context"
      }
    end
  end
end
