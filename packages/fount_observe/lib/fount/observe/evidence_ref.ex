defmodule Fount.Observe.EvidenceRef do
  @moduledoc "Exact evidence validated against the supplied canonical revision before acquisition."
  alias Fount.Observe.{Error, TargetRef}
  @enforce_keys [:id, :screenplay_id, :revision_id, :target, :excerpt, :excerpt_sha256]
  defstruct [
    :id,
    :screenplay_id,
    :revision_id,
    :target,
    :excerpt,
    :excerpt_sha256,
    role: "input_context"
  ]

  @type t :: %__MODULE__{}

  def from_source(model, entry) when is_map(entry) do
    resolver = fn screenplay_id, revision_id, target ->
      with true <- screenplay_id == model.id and revision_id == model.revision.id,
           {:ok, element} <- Fount.Target.resolve(model, target),
           text when is_binary(text) <- Map.get(element, :text) do
        {:ok, text}
      else
        _ -> {:error, :source_identity_mismatch}
      end
    end

    with {:ok, _} <- Fount.SourceEvidence.validate([entry], resolver),
         {:ok, target} <- TargetRef.from_source(model, entry["target"]) do
      {:ok,
       %__MODULE__{
         id: entry["evidence_id"],
         screenplay_id: model.id,
         revision_id: model.revision.id,
         target: target,
         excerpt: entry["excerpt"],
         excerpt_sha256: :crypto.hash(:sha256, entry["excerpt"]) |> Base.encode16(case: :lower),
         role: entry["role"] || "input_context"
       }}
    else
      _ -> {:error, Error.at(:invalid_target, ["evidence"])}
    end
  end

  def from_source(_, _), do: {:error, Error.at(:invalid_target, ["evidence"])}

  def to_map(%__MODULE__{} = ref) do
    %{
      "evidence_id" => ref.id,
      "screenplay_id" => ref.screenplay_id,
      "revision_id" => ref.revision_id,
      "target" => TargetRef.to_map(ref.target),
      "excerpt" => ref.excerpt,
      "excerpt_sha256" => ref.excerpt_sha256,
      "role" => ref.role
    }
  end
end
