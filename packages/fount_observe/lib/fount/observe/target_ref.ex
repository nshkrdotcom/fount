defmodule Fount.Observe.TargetRef do
  @moduledoc "A canonical source identity or an explicitly run-local analytical subject."
  alias Fount.Observe.Error
  @enforce_keys [:screenplay_id, :revision_id, :kind, :id]
  defstruct [:screenplay_id, :revision_id, :kind, :id, :span]
  @type t :: %__MODULE__{}

  def from_source(model, %{"kind" => "semantic_subject", "id" => id}) when is_binary(id) and id != "",
    do: {:ok, %__MODULE__{screenplay_id: model.id, revision_id: model.revision.id, kind: "semantic_subject", id: id}}
  def from_source(model, %{"kind" => kind, "id" => id} = target) when is_binary(kind) and is_binary(id) do
    with {:ok, _} <- Fount.Selection.target_ids(model, target) do
      {:ok, %__MODULE__{screenplay_id: model.id, revision_id: model.revision.id, kind: kind, id: id, span: target["span"]}}
    else
      _ -> {:error, Error.at(:invalid_target, ["target"])}
    end
  end
  def from_source(_, _), do: {:error, Error.at(:invalid_target, ["target"])}

  def to_map(%__MODULE__{} = ref) do
    %{"screenplay_id" => ref.screenplay_id, "revision_id" => ref.revision_id,
      "kind" => ref.kind, "id" => ref.id, "span" => ref.span}
  end
end
