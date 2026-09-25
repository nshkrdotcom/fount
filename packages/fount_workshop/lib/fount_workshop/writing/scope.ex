defmodule FountWorkshop.Writing.Scope do
  @moduledoc "Checks the writer's exact edit authority before replay and against the result."

  alias Fount.Query
  alias FountProbe.Projection

  def operations(_, _, nil, _), do: :ok
  def operations(_, _, %{"whole_screenplay" => true}, _), do: :ok

  def operations(base, edits, selection, placement) do
    with {:ok, allowed} <- Projection.selected_ids(base, selection) do
      targets = Map.get(selection, "targets", [])
      full = full_ids(base, targets)

      violations =
        Enum.flat_map(edits, fn edit ->
          if authorized?(base, edit, allowed, full, targets, placement),
            do: [],
            else: [edit_identity(edit)]
        end)

      repeated_spans =
        edits
        |> Enum.flat_map(fn
          %{"kind" => "replace_text", "target" => %{"id" => id, "span" => span}}
          when not is_nil(span) ->
            if MapSet.member?(full, id), do: [], else: [id]

          _ ->
            []
        end)
        |> Enum.frequencies()
        |> Enum.flat_map(fn {id, count} -> if count > 1, do: [id], else: [] end)

      violations = violations ++ repeated_spans

      if violations == [], do: :ok, else: {:error, {:outside_editable_scope, violations}}
    end
  end

  def result(_, _, nil), do: :ok
  def result(_, _, %{"whole_screenplay" => true}), do: :ok

  def result(base, draft, selection) do
    with {:ok, allowed} <- Projection.selected_ids(base, selection) do
      changed =
        Enum.filter(base.ir.elements, fn element ->
          next = Query.node(draft, element.id)

          is_nil(next) or
            Map.take(next, [:text, :type, :attrs]) != Map.take(element, [:text, :type, :attrs])
        end)

      outside = Enum.reject(changed, &MapSet.member?(allowed, &1.id)) |> Enum.map(& &1.id)

      moved =
        Enum.flat_map(base.ir.elements, fn element ->
          if MapSet.member?(allowed, element.id) or is_nil(Query.node(draft, element.id)) do
            []
          else
            before_owner = Query.scene_for(base, element.id)
            after_owner = Query.scene_for(draft, element.id)

            if (before_owner && before_owner.id) != (after_owner && after_owner.id),
              do: [element.id],
              else: []
          end
        end)

      outside_scene_ids =
        base.ir.scenes
        |> Enum.reject(&MapSet.member?(allowed, &1.heading_id))
        |> Enum.map(& &1.id)

      before = Enum.filter(Enum.map(base.ir.scenes, & &1.id), &(&1 in outside_scene_ids))
      after_order = Enum.filter(Enum.map(draft.ir.scenes, & &1.id), &(&1 in outside_scene_ids))

      violations = outside ++ moved ++ if(before == after_order, do: [], else: outside_scene_ids)

      if violations == [],
        do: :ok,
        else: {:error, {:outside_editable_scope, Enum.uniq(violations)}}
    end
  end

  defp full_ids(base, targets) do
    Enum.reduce(targets, MapSet.new(), fn target, acc ->
      if target["kind"] == "element" and not is_nil(target["span"]) do
        acc
      else
        case Projection.target_ids(base, target) do
          {:ok, ids} ->
            acc = Enum.reduce(ids, acc, &MapSet.put(&2, &1))
            if target["kind"] == "scene", do: MapSet.put(acc, target["id"]), else: acc

          _ ->
            acc
        end
      end
    end)
  end

  defp authorized?(
         _base,
         %{"kind" => "replace_text", "target" => target},
         allowed,
         full,
         targets,
         _
       ) do
    id = target["id"]

    MapSet.member?(allowed, id) and
      (MapSet.member?(full, id) or span_authorized?(target["span"], targets, id))
  end

  defp authorized?(_, %{"kind" => kind, "target" => target}, _, full, _, _)
       when kind in ~w(set_scene_heading set_scene_number omit_scene delete_scene move_scene replace_scene_body) do
    MapSet.member?(full, target["id"])
  end

  defp authorized?(base, %{"kind" => "insert_elements", "target" => target}, _, full, _, _) do
    target["kind"] == "scene" and
      case Query.scene(base, target["id"]) do
        nil -> false
        scene -> MapSet.member?(full, scene.heading_id)
      end
  end

  defp authorized?(_, %{"kind" => "delete_elements", "value" => %{"ids" => ids}}, _, full, _, _),
    do: Enum.all?(ids, &MapSet.member?(full, &1))

  defp authorized?(
         base,
         %{"kind" => "replace_sequence", "value" => %{"scene_ids" => ids}},
         _,
         full,
         _,
         _
       ),
       do:
         Enum.all?(ids, fn id ->
           scene = Query.scene(base, id)
           scene && MapSet.member?(full, scene.heading_id)
         end)

  defp authorized?(
         base,
         %{"kind" => "insert_scene", "value" => %{"after_scene_id" => after_id}},
         _,
         full,
         _,
         placement
       ) do
    case placement do
      %{"kind" => "between_scenes", "after_scene_id" => ^after_id} ->
        true

      %{"kind" => "after_scene", "after_scene_id" => ^after_id} ->
        true

      %{"kind" => "start"} when is_nil(after_id) ->
        true

      _ ->
        scene = after_id && Query.scene(base, after_id)
        scene && MapSet.member?(full, scene.heading_id)
    end
  end

  defp authorized?(_, %{"kind" => "link_speaker", "target" => target}, _, full, _, _),
    do: MapSet.member?(full, target["id"])

  defp authorized?(base, %{"kind" => "put_character", "value" => value}, _, _, _, _) do
    is_nil(base.cast[value["id"]])
  end

  defp authorized?(base, %{"kind" => "put_authored_item", "value" => value}, allowed, _, _, _) do
    is_nil(base.authored_items[value["id"]]) and
      case Projection.target_ids(base, value["target"]) do
        {:ok, ids} -> ids != [] and Enum.all?(ids, &MapSet.member?(allowed, &1))
        _ -> false
      end
  end

  defp authorized?(_, _, _, _, _, _), do: false

  defp span_authorized?(%{"byte_start" => first, "byte_end" => last}, targets, id) do
    Enum.any?(targets, fn
      %{
        "kind" => "element",
        "id" => ^id,
        "span" => %{"byte_start" => start, "byte_end" => finish}
      } ->
        first >= start and last <= finish

      _ ->
        false
    end)
  end

  defp span_authorized?(_, _, _), do: false

  defp edit_identity(edit), do: edit["target"]["id"] || edit["kind"]
end
