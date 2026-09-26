defmodule Fount.Target do
  @moduledoc "Resolve a typed target within one screenplay revision."
  def resolve(model, %{"kind" => kind, "id" => id}), do: resolve(model, %{kind: kind, id: id})

  def resolve(model, %{kind: kind, id: id}) do
    value = resolve_kind(model, to_string(kind), id)

    if value, do: {:ok, value}, else: {:error, :missing_target}
  end

  def resolve(_, _), do: {:error, :invalid_target}

  defp resolve_kind(model, "screenplay", id), do: if(model.id == id, do: model)
  defp resolve_kind(model, "revision", id), do: if(model.revision.id == id, do: model.revision)
  defp resolve_kind(model, "element", id), do: Fount.Query.node(model, id)
  defp resolve_kind(model, "scene", id), do: Fount.Query.scene(model, id)
  defp resolve_kind(model, "dialogue_block", id), do: Fount.Query.dialogue_block(model, id)
  defp resolve_kind(model, "character", id), do: model.cast[id]
  defp resolve_kind(model, "authored_item", id), do: model.authored_items[id]

  defp resolve_kind(model, "title_entry", id),
    do: Enum.find((model.ir.title_page && model.ir.title_page.entries) || [], &(&1.id == id))

  defp resolve_kind(_, _, _), do: nil
end
