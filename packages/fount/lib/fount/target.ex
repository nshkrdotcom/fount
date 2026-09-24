defmodule Fount.Target do
  @moduledoc "Resolve a typed target within one screenplay revision."
  def resolve(model, %{"kind" => kind, "id" => id}), do: resolve(model, %{kind: kind, id: id})

  def resolve(model, %{kind: kind, id: id}) do
    value =
      case to_string(kind) do
        "screenplay" -> if model.id == id, do: model
        "revision" -> if model.revision.id == id, do: model.revision
        "element" -> Fount.Query.node(model, id)
        "scene" -> Fount.Query.scene(model, id)
        "dialogue_block" -> Fount.Query.dialogue_block(model, id)
        "character" -> model.cast[id]
        "authored_item" -> model.authored_items[id]
        "title_entry" -> Enum.find((model.ir.title_page && model.ir.title_page.entries) || [], &(&1.id == id))
        _ -> nil
      end

    if value, do: {:ok, value}, else: {:error, :missing_target}
  end

  def resolve(_, _), do: {:error, :invalid_target}
end
