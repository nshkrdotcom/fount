defmodule Fount.Intelligence.StoryWorld.Evidence do
  @moduledoc "Pure, serializable source evidence retained by StoryWorld values and domain-review renderers."

  alias Fount.Intelligence.StoryWorld.Evidence
  alias Fount.Observe.{EvidenceRef, TargetRef}

  @enforce_keys [:id, :screenplay_id, :revision_id, :target]
  defstruct [:id, :screenplay_id, :revision_id, :target, :excerpt, :excerpt_sha256, :role, metadata: %{}]
  @type t :: %__MODULE__{}

  def from_observe(%EvidenceRef{} = ref) do
    %Evidence{
      id: ref.id,
      screenplay_id: ref.screenplay_id,
      revision_id: ref.revision_id,
      target: TargetRef.to_map(ref.target),
      excerpt: ref.excerpt,
      excerpt_sha256: ref.excerpt_sha256,
      role: ref.role
    }
  end

  def from_source_map(model, %{} = entry) do
    with id when is_binary(id) and id != "" <- entry["evidence_id"] || entry[:evidence_id],
         screenplay_id when screenplay_id == model.id <- entry["screenplay_id"] || entry[:screenplay_id],
         revision_id when revision_id == model.revision.id <- entry["revision_id"] || entry[:revision_id],
         %{} = target <- entry["target"] || entry[:target],
         excerpt when is_binary(excerpt) <- entry["excerpt"] || entry[:excerpt],
         :ok <- validate_source(model, screenplay_id, revision_id, target, excerpt) do
      {:ok,
       %Evidence{
         id: id,
         screenplay_id: screenplay_id,
         revision_id: revision_id,
         target: stringify_keys(target),
         excerpt: excerpt,
         excerpt_sha256: Fount.ID.hash(excerpt),
         role: entry["role"] || entry[:role] || "story_world_support"
       }}
    else
      _ -> {:error, :invalid_story_world_evidence}
    end
  end

  def from_source_map(_model, _entry), do: {:error, :invalid_story_world_evidence}

  def canonical_element(model, element, role \\ "canonical_source") do
    excerpt = element.text || ""

    %Evidence{
      id: "sw_ev_" <> Fount.ID.hash([model.revision.id, ":", element.id, ":", excerpt]),
      screenplay_id: model.id,
      revision_id: model.revision.id,
      target: %{
        "kind" => "element",
        "id" => element.id,
        "span" => %{"byte_start" => 0, "byte_end" => byte_size(excerpt)}
      },
      excerpt: excerpt,
      excerpt_sha256: Fount.ID.hash(excerpt),
      role: role
    }
  end

  defp validate_source(model, screenplay_id, revision_id, target, excerpt) do
    resolver = fn supplied_screenplay, supplied_revision, supplied_target ->
      with true <- supplied_screenplay == model.id,
           true <- supplied_revision == model.revision.id,
           {:ok, element} <- Fount.Target.resolve(model, supplied_target),
           text when is_binary(text) <- Map.get(element, :text) do
        {:ok, text}
      else
        _ -> {:error, :source_identity_mismatch}
      end
    end

    source = %{
      "evidence_id" => "story_world_validation",
      "screenplay_id" => screenplay_id,
      "revision_id" => revision_id,
      "target" => stringify_keys(target),
      "excerpt" => excerpt
    }

    case Fount.SourceEvidence.validate([source], resolver) do
      {:ok, _} -> :ok
      _ -> {:error, :invalid_story_world_evidence}
    end
  end

  defp stringify_keys(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), stringify_keys(item)} end)

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
