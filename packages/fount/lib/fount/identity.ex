defmodule Fount.Identity do
  @moduledoc """
  Stable identity reconciliation across reparses and persisted sidecars.

  IDs are not derived from current byte position after a document has history.
  Reconciliation matches semantic signatures and uses neighboring signatures plus
  old ordinal as deterministic tie-breakers for repeated identical elements.
  """

  alias Fount.IR
  alias Fount.IR.{Element, Script, TitlePage}

  @known_types ~w(scene_heading action character dialogue parenthetical transition centered lyric section synopsis page_break note boneyard blank)
               |> Map.new(&{&1, String.to_atom(&1)})

  @type hint :: %{
          required(:old_id) => String.t(),
          required(:type) => atom(),
          optional(:byte_start) => non_neg_integer()
        }

  @spec reconcile(Script.t(), Script.t(), [hint()]) :: Script.t()
  def reconcile(%Script{} = old, %Script{} = new, hints \\ []) do
    {script, _id_map} = reconcile_with_map(old, new, hints)
    script
  end

  @spec reconcile_with_map(Script.t(), Script.t(), [hint()]) :: {Script.t(), map()}
  def reconcile_with_map(%Script{} = old, %Script{} = new, hints \\ []) do
    id_map = old |> anchors() |> contextual_id_map(new) |> apply_hints(new, hints)
    {IR.remap_ids(new, id_map), id_map}
  end

  @spec anchors(Script.t()) :: [map()]
  def anchors(%Script{} = script) do
    element_anchors(script.elements) ++ title_anchors(script.title_page)
  end

  @doc "Warn when a reparse changes a source-backed object without a confident identity match."
  @spec reconciliation_diagnostics(Script.t(), Script.t()) :: [Fount.Diagnostic.t()]
  def reconciliation_diagnostics(%Script{} = old, %Script{} = new) do
    old_ids = MapSet.new(Enum.map(old.elements, & &1.id))
    new_ids = MapSet.new(Enum.map(new.elements, & &1.id))

    unmatched_types =
      new.elements
      |> Enum.reject(&MapSet.member?(old_ids, &1.id))
      |> Enum.map(& &1.type)
      |> MapSet.new()

    old.elements
    |> Enum.reject(&MapSet.member?(new_ids, &1.id))
    |> Enum.filter(&MapSet.member?(unmatched_types, &1.type))
    |> Enum.map(fn element ->
      %Fount.Diagnostic{
        severity: :warning,
        code: :identity_not_retained,
        message: "Could not safely retain #{element.type} identity after source change.",
        span: element.source_span,
        node_id: element.id
      }
    end)
  end

  @doc "Restore persisted IDs by semantic signature and local context."
  @spec restore(Script.t(), [map()]) :: Script.t()
  def restore(%Script{} = script, anchors) when is_list(anchors) do
    {script, _id_map} = restore_with_map(script, anchors)
    script
  end

  @spec restore_with_map(Script.t(), [map()]) :: {Script.t(), map()}
  def restore_with_map(%Script{} = script, anchors) when is_list(anchors) do
    id_map = contextual_id_map(anchors, script)
    {IR.remap_ids(script, id_map), id_map}
  end

  defp element_anchors(elements) do
    signatures = Enum.map(elements, &element_signature/1)

    elements
    |> Enum.with_index()
    |> Enum.map(fn {element, index} ->
      %{
        "scope" => "element",
        "id" => element.id,
        "type" => Atom.to_string(element.type),
        "text_hash" => elem(Enum.at(signatures, index), 1),
        "previous_hash" => neighbor_hash(signatures, index - 1),
        "next_hash" => neighbor_hash(signatures, index + 1),
        "ordinal" => index
      }
    end)
  end

  defp title_anchors(nil), do: []

  defp title_anchors(%TitlePage{entries: entries}) do
    signatures = Enum.map(entries, &title_signature/1)

    entries
    |> Enum.with_index()
    |> Enum.map(fn {entry, index} ->
      %{
        "scope" => "title_page",
        "id" => entry.id,
        "key" => entry.key,
        "value_hash" => elem(Enum.at(signatures, index), 1),
        "previous_hash" => neighbor_hash(signatures, index - 1),
        "next_hash" => neighbor_hash(signatures, index + 1),
        "ordinal" => index
      }
    end)
  end

  defp contextual_id_map(anchors, %Script{} = script) do
    element_map = contextual_element_map(anchors, script.elements)
    title_map = contextual_title_map(anchors, script.title_page)
    Map.merge(element_map, title_map)
  end

  defp contextual_element_map(anchors, elements) do
    signatures = Enum.map(elements, &element_signature/1)
    candidates = candidate_indexes(signatures)

    anchors
    |> Enum.filter(&element_anchor?/1)
    |> Enum.sort_by(&anchor_ordinal/1)
    |> match_anchors(elements, signatures, candidates, &element_anchor_signature/1)
  end

  defp contextual_title_map(_anchors, nil), do: %{}

  defp contextual_title_map(anchors, %TitlePage{entries: entries}) do
    signatures = Enum.map(entries, &title_signature/1)
    candidates = candidate_indexes(signatures)
    title_anchors = Enum.filter(anchors, &(&1["scope"] == "title_page"))

    exact =
      title_anchors
      |> Enum.sort_by(&anchor_ordinal/1)
      |> match_anchors(entries, signatures, candidates, &title_anchor_signature/1)

    retain_unique_title_keys(exact, title_anchors, entries)
  end

  defp retain_unique_title_keys(id_map, anchors, entries) do
    old_counts = Enum.frequencies_by(anchors, & &1["key"])
    new_counts = Enum.frequencies_by(entries, & &1.key)
    used_old = MapSet.new(Map.values(id_map))

    Enum.reduce(anchors, id_map, fn anchor, acc ->
      key = anchor["key"]

      if old_counts[key] == 1 and new_counts[key] == 1 and not MapSet.member?(used_old, anchor["id"]) do
        entry = Enum.find(entries, &(&1.key == key))
        Map.put_new(acc, entry.id, anchor["id"])
      else
        acc
      end
    end)
  end

  defp candidate_indexes(signatures) do
    signatures
    |> Enum.with_index()
    |> Enum.group_by(fn {signature, _index} -> signature end, fn {_signature, index} -> index end)
  end

  defp match_anchors(anchors, items, signatures, candidates, anchor_signature_fun) do
    anchors
    |> Enum.reduce({%{}, MapSet.new(), MapSet.new()}, fn anchor, {map, used_new, used_old} ->
      old_id = anchor["id"]
      signature = anchor_signature_fun.(anchor)

      available =
        candidates
        |> Map.get(signature, [])
        |> Enum.reject(&MapSet.member?(used_new, &1))

      cond do
        not is_binary(old_id) ->
          {map, used_new, used_old}

        MapSet.member?(used_old, old_id) ->
          {map, used_new, used_old}

        available == [] ->
          {map, used_new, used_old}

        true ->
          index = Enum.min_by(available, &candidate_score(anchor, &1, signatures))
          item = Enum.at(items, index)

          {
            Map.put(map, item.id, old_id),
            MapSet.put(used_new, index),
            MapSet.put(used_old, old_id)
          }
      end
    end)
    |> elem(0)
  end

  defp candidate_score(anchor, index, signatures) do
    previous_penalty = mismatch_penalty(anchor["previous_hash"], neighbor_hash(signatures, index - 1))
    next_penalty = mismatch_penalty(anchor["next_hash"], neighbor_hash(signatures, index + 1))
    distance = abs(index - anchor_ordinal(anchor))
    {previous_penalty + next_penalty, distance, index}
  end

  defp mismatch_penalty(nil, nil), do: 0
  defp mismatch_penalty(nil, _), do: 1
  defp mismatch_penalty(_, nil), do: 1
  defp mismatch_penalty(value, value), do: 0
  defp mismatch_penalty(_, _), do: 4

  defp anchor_ordinal(%{"ordinal" => ordinal}) when is_integer(ordinal), do: ordinal
  defp anchor_ordinal(_), do: 0

  defp element_anchor?(%{"scope" => "title_page"}), do: false
  defp element_anchor?(_), do: true

  defp element_anchor_signature(anchor), do: {safe_type(anchor["type"]), anchor["text_hash"]}
  defp title_anchor_signature(anchor), do: {anchor["key"], anchor["value_hash"]}

  defp apply_hints(id_map, %Script{} = new, hints) do
    Enum.reduce(hints, id_map, &apply_hint(&1, &2, new.elements))
  end

  defp apply_hint(hint, id_map, elements) do
    if hint.old_id in Map.values(id_map) do
      id_map
    else
      case best_hint_target(elements, hint, MapSet.new(Map.keys(id_map))) do
        nil -> id_map
        %Element{} = element -> Map.put(id_map, element.id, hint.old_id)
      end
    end
  end

  defp best_hint_target(elements, hint, already_mapped) do
    elements
    |> Enum.reject(&MapSet.member?(already_mapped, &1.id))
    |> Enum.filter(&(&1.type == hint.type))
    |> Enum.min_by(
      fn element ->
        case {Map.get(hint, :byte_start), element.source_span} do
          {offset, %{byte_start: start}} when is_integer(offset) -> abs(start - offset)
          _ -> 0
        end
      end,
      fn -> nil end
    )
  end

  defp element_signature(%Element{} = element) do
    {element.type, Fount.ID.short_hash([element.text || "", ":", identity_attrs(element)])}
  end

  defp title_signature(entry) do
    {entry.key, Fount.ID.short_hash([entry.key, "\0", Enum.intersperse(entry.values, "\0")])}
  end

  defp identity_attrs(%Element{type: :scene_heading, attrs: attrs}),
    do: to_string(Map.get(attrs || %{}, :number, ""))

  defp identity_attrs(%Element{type: :character, attrs: attrs}),
    do: to_string(Map.get(attrs || %{}, :extension, ""))

  defp identity_attrs(_), do: ""

  defp neighbor_hash(_signatures, index) when index < 0, do: nil

  defp neighbor_hash(signatures, index) do
    case Enum.at(signatures, index) do
      nil -> nil
      {_type, hash} -> hash
    end
  end

  defp safe_type(type) when is_atom(type), do: type

  defp safe_type(type) when is_binary(type), do: Map.get(@known_types, type, :unknown)

  defp safe_type(_), do: :unknown
end
