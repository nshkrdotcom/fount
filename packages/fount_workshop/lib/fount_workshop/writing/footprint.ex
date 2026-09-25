defmodule FountWorkshop.Writing.Footprint do
  @moduledoc false
  def groups(base, groups), do: Map.new(groups, fn g -> {g["id"], Enum.flat_map(g["operations"], &operation(base, &1))} end)
  def overlaps(base, groups) do
    footprints = groups(base, groups)
    for {a, i} <- Enum.with_index(groups), {b, j} <- Enum.with_index(groups), i < j,
      Enum.any?(footprints[a["id"]], fn x -> Enum.any?(footprints[b["id"]], &overlap?(x, &1)) end),
      do: %{"left" => a["id"], "right" => b["id"], "reason" => "shared_edit_surface"}
  end
  def operation(_, %{"kind" => "replace_text", "target" => t}), do: [{"element", t["id"], t["span"]}]
  def operation(_, %{"kind" => "delete_elements", "value" => %{"ids" => ids}}), do: Enum.map(ids, &{"element", &1, nil})
  def operation(base, %{"kind" => "replace_sequence", "value" => %{"scene_ids" => ids}}), do: Enum.flat_map(ids, &scene(base, &1))
  def operation(base, %{"kind" => kind, "target" => %{"kind" => "scene", "id" => id}}) when kind in ~w(delete_scene replace_scene_body move_scene omit_scene), do: scene(base, id)
  def operation(base, %{"kind" => "set_scene_heading", "target" => t}), do: [{"element", Fount.Query.scene(base, t["id"]).heading_id, nil}]
  def operation(_, %{"kind" => "insert_scene", "value" => v}), do: [{"scene_gap", v["after_scene_id"], nil}]
  def operation(_, %{"kind" => "insert_elements", "target" => t, "value" => v}), do: [{"element_gap", {t["id"], v["position"], v["anchor_id"]}, nil}]
  def operation(base, %{"kind" => "rename_character", "target" => t, "value" => v}) do
    cue_ids = Fount.Query.character_dialogue(base, t["id"]) |> Enum.map(& &1.cue_id)
    mention_ids = Enum.flat_map(v["mention_ids"], fn id -> case base.mentions[id] do nil -> []; m -> [m.element_id] end end)
    [{"character", t["id"], nil} | Enum.map(cue_ids ++ mention_ids, &{"element", &1, nil})]
  end
  def operation(_, %{"target" => t}), do: [{t["kind"], t["id"], nil}]
  def operation(_, %{"kind" => "set_title"}), do: [{"title", "all", nil}]
  def operation(_, %{"kind" => kind, "value" => v}) when kind in ~w(put_character put_authored_item), do: [{kind, v["id"] || v["local_id"], nil}]
  def operation(_, _), do: []
  defp scene(base, id) do
    case Fount.Query.scene(base, id) do nil -> [{"scene", id, nil}]; s -> [{"scene", id, nil} | Enum.map(s.element_ids, &{"element", &1, nil})] end
  end
  defp overlap?({kind, id, a}, {kind, id, b}) do
    is_nil(a) or is_nil(b) or (a["byte_start"] < b["byte_end"] and b["byte_start"] < a["byte_end"])
  end
  defp overlap?(_, _), do: false
end
