defmodule FountProbe.State do
  @moduledoc "Exact screenplay views for questions about what an audience or speaker has seen."

  alias Fount.Query

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

  @doc "Returns only active scenes before the selected scene, with exact element IDs."
  def audience_before(model, scene_id) do
    case Enum.find_index(model.ir.scenes, &(&1.id == scene_id)) do
      nil ->
        {:error, :unknown_scene}

      boundary ->
        scenes = model.ir.scenes |> Enum.take(boundary) |> Enum.reject(& &1.omitted?)
        {:ok, view(model, scenes, "audience", nil)}
    end
  end

  @doc "Uses only earlier scenes with a confirmed speaking cue for this character."
  def speaker_before(model, character_id, scene_id) do
    with true <- Map.has_key?(model.cast, character_id),
         {:ok, audience} <- audience_before(model, scene_id) do
      scene_ids = audience["scene_ids"] |> MapSet.new()

      spoken =
        model.mentions
        |> Map.values()
        |> Enum.filter(
          &(&1.character_id == character_id and &1.role == :speaker_cue and
              &1.status == :confirmed)
        )
        |> Enum.map(&Query.scene_for(model, &1.element_id))
        |> Enum.reject(&is_nil/1)
        |> Enum.map(& &1.id)
        |> MapSet.new()

      scenes =
        Enum.filter(
          model.ir.scenes,
          &(MapSet.member?(scene_ids, &1.id) and MapSet.member?(spoken, &1.id))
        )

      {:ok, view(model, scenes, "speaker", character_id)}
    else
      false -> {:error, :unknown_character}
      error -> error
    end
  end

  defp view(model, scenes, perspective, character_id) do
    elements =
      model |> Fount.Screenplay.Editor.spec_ir() |> Map.fetch!(:elements) |> Map.new(&{&1.id, &1})

    %{
      "screenplay_id" => model.id,
      "revision_id" => model.revision.id,
      "perspective" => perspective,
      "character_id" => character_id,
      "scene_ids" => Enum.map(scenes, & &1.id),
      "scenes" =>
        Enum.map(scenes, fn scene ->
          %{
            "id" => scene.id,
            "elements" =>
              scene.element_ids
              |> Enum.map(&elements[&1])
              |> Enum.filter(&(&1 && &1.type in @visible_types))
              |> Enum.map(&%{"id" => &1.id, "type" => to_string(&1.type), "text" => &1.text})
          }
        end)
    }
  end
end
