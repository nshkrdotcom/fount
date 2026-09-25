defmodule FountProbe.State do
  @moduledoc "Convenience views backed by the exact access-aware projection."
  def audience_before(model, scene_id), do: view(model, scene_id, "audience_estimate", [])
  def speaker_before(model, character_id, scene_id), do: view(model, scene_id, "character_access", character_id: character_id)
  defp view(model, scene_id, projection, opts) do
    point = %{"scene_id" => scene_id, "through_element_id" => nil}
    with {:ok, state, evidence} <- FountProbe.Projection.at(model, point, projection, opts) do
      by_evidence = Map.new(state["material"], &{&1["evidence_id"], &1})
      scenes = evidence |> Enum.group_by(fn e -> s = Fount.Query.scene_for(model, e["target"]["id"]); s && s.id end)
      ordered = model.ir.scenes |> Enum.filter(&Map.has_key?(scenes, &1.id)) |> Enum.map(fn s ->
        %{"id" => s.id, "elements" => Enum.map(scenes[s.id], fn e -> %{"id" => e["target"]["id"], "text" => by_evidence[e["evidence_id"]]["text"], "type" => by_evidence[e["evidence_id"]]["type"]} end)}
      end)
      {:ok, Map.merge(state, %{"perspective" => projection, "scenes" => ordered, "scene_ids" => Enum.map(ordered, & &1["id"])})}
    end
  end
end
