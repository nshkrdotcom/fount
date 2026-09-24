defmodule Fount.Diff do
  @moduledoc "Source and semantic diffs between screenplay revisions."

  alias Fount.Document

  @spec source(Document.t(), Document.t()) :: list()
  def source(%Document{} = left, %Document{} = right) do
    if String.valid?(left.source.raw) and String.valid?(right.source.raw) do
      String.myers_difference(left.source.raw, right.source.raw)
    else
      List.myers_difference(:binary.bin_to_list(left.source.raw), :binary.bin_to_list(right.source.raw))
    end
  end

  @spec semantic(Document.t(), Document.t()) :: map()
  def semantic(%Document{} = left, %Document{} = right) do
    left_map = Map.new(left.ir.elements, &{&1.id, &1})
    right_map = Map.new(right.ir.elements, &{&1.id, &1})
    left_ids = Map.keys(left_map) |> MapSet.new()
    right_ids = Map.keys(right_map) |> MapSet.new()

    inserted = MapSet.difference(right_ids, left_ids) |> Enum.map(&Map.fetch!(right_map, &1))
    deleted = MapSet.difference(left_ids, right_ids) |> Enum.map(&Map.fetch!(left_map, &1))
    common = MapSet.intersection(left_ids, right_ids)

    modified =
      common
      |> Enum.flat_map(fn id ->
        a = Map.fetch!(left_map, id)
        b = Map.fetch!(right_map, id)

        if {a.type, a.text, a.attrs} == {b.type, b.text, b.attrs} do
          []
        else
          [%{id: id, before: a, after: b, text_diff: text_diff(a.text, b.text)}]
        end
      end)

    left_pos = left.ir.elements |> Enum.with_index() |> Map.new(fn {e, i} -> {e.id, i} end)
    right_pos = right.ir.elements |> Enum.with_index() |> Map.new(fn {e, i} -> {e.id, i} end)

    moved =
      common
      |> Enum.flat_map(fn id ->
        if left_pos[id] == right_pos[id], do: [], else: [%{id: id, from: left_pos[id], to: right_pos[id]}]
      end)

    %{inserted: inserted, deleted: deleted, modified: modified, moved: moved}
  end

  defp text_diff(a, b) do
    if String.valid?(a) and String.valid?(b), do: String.myers_difference(a, b), else: []
  end
end
