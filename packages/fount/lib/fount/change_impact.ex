defmodule Fount.ChangeImpact do
  @moduledoc "Changed identities and their screenplay, scene, block and cast dependents."
  def between(before, after_model) do
    a = objects(before)
    b = objects(after_model)
    inserted = for {key, _} <- b, not Map.has_key?(a, key), do: target(key)
    removed = for {key, _} <- a, not Map.has_key?(b, key), do: target(key)
    changed = for {key, value} <- a, Map.has_key?(b, key) and b[key] != value, do: target(key)
    direct = inserted ++ removed ++ changed
    parents = Enum.flat_map(direct, fn t -> parents(before, t) ++ parents(after_model, t) end)
    %{changed_targets: Enum.uniq(changed ++ parents), inserted_targets: inserted, removed_targets: removed}
  end

  defp objects(m) do
    pairs =
      for {kind, values} <- [
            element: m.ir.elements,
            scene: m.ir.scenes,
            dialogue_block: m.ir.dialogue_blocks,
            character: Map.values(m.cast)
          ],
          v <- values,
          do: {{kind, v.id}, v}

    Map.new(pairs ++ Enum.map(m.authored_items, fn {id, v} -> {{:authored_item, id}, v} end))
  end

  defp target({kind, id}), do: %{kind: kind, id: id}

  defp parents(m, %{kind: :element, id: id}) do
    scene = Fount.Query.scene_for(m, id)
    block = Fount.Query.block_for(m, id)

    [%{kind: :screenplay, id: m.id}] ++
      if(scene, do: [%{kind: :scene, id: scene.id}], else: []) ++
      if block, do: [%{kind: :dialogue_block, id: block.id}], else: []
  end

  defp parents(m, %{kind: :character, id: id}),
    do: [
      %{kind: :screenplay, id: m.id}
      | Enum.map(Fount.Query.character_mentions(m, id), &%{kind: :element, id: &1.element_id})
    ]

  defp parents(m, _), do: [%{kind: :screenplay, id: m.id}]
end
