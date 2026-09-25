defmodule Fount.Writing.Structure do
  @moduledoc "Scene split/merge conveniences expressed as canonical typed edits."
  def split(model, scene_id, after_element_id, new_heading, opts \\ []) do
    with %Fount.IR.Scene{} = scene <- Fount.Query.scene(model, scene_id),
         {:ok, _} <- Fount.Slice.scene_prefix(model, scene_id, after_element_id),
         true <- after_element_id in scene.element_ids or {:error, :wrong_scene_cutoff},
         body = tl(scene.element_ids),
         index = Enum.find_index(body, &(&1 == after_element_id)),
         true <- (is_integer(index) and index < length(body) - 1) or {:error, :empty_split_side} do
      {left, right} = Enum.split(body, index + 1)

      scenes = [
        spec(model, scene, left),
        %{"local_id" => "new:split-scene", "heading" => new_heading, "elements" => Enum.map(right, &%{"keep" => &1})}
      ]

      Fount.Screenplay.apply(
        model,
        [%{"kind" => "replace_sequence", "value" => %{"scene_ids" => [scene_id], "scenes" => scenes}}],
        opts
      )
    else
      nil -> {:error, :unknown_scene}
      {:error, _} = error -> error
      _ -> {:error, :invalid_split}
    end
  end

  def merge(model, scene_ids, heading, opts \\ [])

  def merge(model, scene_ids, heading, opts) when is_list(scene_ids) and length(scene_ids) >= 2 do
    scenes = Enum.map(scene_ids, &Fount.Query.scene(model, &1))

    if Enum.any?(scenes, &is_nil/1) do
      {:error, :unknown_scene}
    else
      first = hd(scenes)
      body = Enum.flat_map(scenes, &tl(&1.element_ids))
      merged = spec(model, first, body) |> Map.put("heading", heading || Fount.Query.node(model, first.heading_id).text)

      Fount.Screenplay.apply(
        model,
        [%{"kind" => "replace_sequence", "value" => %{"scene_ids" => scene_ids, "scenes" => [merged]}}],
        opts
      )
    end
  end

  def merge(_, _, _, _), do: {:error, :at_least_two_scenes_required}

  defp spec(model, scene, body),
    do: %{
      "id" => scene.id,
      "heading" => Fount.Query.node(model, scene.heading_id).text,
      "number" => scene.number,
      "omitted" => scene.omitted?,
      "elements" => Enum.map(body, &%{"keep" => &1})
    }
end
