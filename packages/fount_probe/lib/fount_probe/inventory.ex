defmodule FountProbe.Inventory do
  @moduledoc "Deterministic scene inventory with exact source IDs and inspected scope."
  alias Fount.Query
  alias Fount.Screenplay.Editor

  @visible_types [
    :scene_heading,
    :action,
    :character,
    :dialogue,
    :parenthetical,
    :transition,
    :centered,
    :lyric,
    :page_break
  ]

  @doc "Lists active scenes without treating notes or omitted material as performed pages."
  def inspect(model, opts \\ []) do
    requested = Keyword.get(opts, :scene_ids)
    known = MapSet.new(Enum.map(model.ir.scenes, & &1.id))

    if requested != nil and
         (not is_list(requested) or
            Enum.any?(requested, &(not MapSet.member?(known, &1)))) do
      {:error, :unknown_scene}
    else
      scenes =
        model.ir.scenes
        |> Enum.reject(& &1.omitted?)
        |> Enum.filter(&(requested == nil or &1.id in requested))

      visible =
        model
        |> Editor.spec_ir()
        |> Map.fetch!(:elements)
        |> Map.new(&{&1.id, &1})

      rows = Enum.map(scenes, &scene_row(model, &1, visible))

      {:ok,
       %{
         screenplay_id: model.id,
         revision_id: model.revision.id,
         status: :complete,
         inspected_scene_ids: Enum.map(scenes, & &1.id),
         omitted_scene_ids: for(scene <- model.ir.scenes, scene.omitted?, do: scene.id),
         scenes: rows
       }}
    end
  end

  defp scene_row(model, scene, visible) do
    elements =
      scene.element_ids
      |> Enum.map(&visible[&1])
      |> Enum.filter(&(&1 && &1.type in @visible_types))

    ids = MapSet.new(Enum.map(elements, & &1.id))

    speaker_ids =
      model.mentions
      |> Map.values()
      |> Enum.filter(
        &(&1.role == :speaker_cue and &1.status == :confirmed and
            MapSet.member?(ids, &1.element_id))
      )
      |> Enum.map(& &1.character_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    %{
      scene_id: scene.id,
      heading: Query.node(model, scene.heading_id).text,
      element_ids: Enum.map(elements, & &1.id),
      speaker_ids: speaker_ids,
      action_words: word_count(elements, :action),
      dialogue_words: word_count(elements, :dialogue)
    }
  end

  defp word_count(elements, type) do
    elements
    |> Enum.filter(&(&1.type == type))
    |> Enum.map(&(String.split(&1.text, ~r/\s+/u, trim: true) |> length()))
    |> Enum.sum()
  end
end
