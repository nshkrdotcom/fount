defmodule Fount.Intelligence.Recomputation do
  @moduledoc """
  Dependency-driven recomputation planning for durable analysis.

  StoryWorld and Reader remain pure and own their existing algorithms: StoryWorld
  expands through the connected story-time/dependency region, while Reader starts
  at the earliest affected presentation checkpoint and recomputes the suffix.
  Persisted diagnoses/reports are selected by explicit dependency intersection.
  Nothing here deletes immutable MeasurementResults.
  """

  alias Fount.Intelligence.{Persistence, Reader, Temporal}
  alias Fount.Intelligence.StoryWorld
  alias Fount.Persistence.Analysis

  @doc "Builds the pure StoryWorld + Reader frontier and, optionally, durable derived dependents."
  def plan(world, reader, changed_dependencies, opts \\ [])

  def plan(%StoryWorld{} = world, %Reader{} = reader, changed_dependencies, opts)
      when is_list(changed_dependencies) and is_list(opts) do
    normalized = normalize(changed_dependencies)

    persisted =
      case Keyword.get(opts, :store) do
        %Persistence{} = store -> persisted_dependents(store, world.screenplay_id, normalized)
        _ -> []
      end

    %{
      "changed_dependencies" => normalized,
      "story_world" => Temporal.recomputation_region(world, normalized),
      "reader" => Reader.recomputation_boundary(reader, normalized),
      "derived_records" => persisted,
      "cache_policy" => %{
        "measurement_results" => "lookup_by_exact_semantic_identity",
        "revision_edit_deletes_cache_rows" => false
      }
    }
  end

  def plan(_, _, _, _), do: {:error, :invalid_recomputation_request}

  @doc "Finds persisted observations/diagnoses/writer packets whose declared dependencies intersect a change."
  def persisted_dependents(%Persistence{} = store, screenplay_id, changed_dependencies)
      when is_binary(screenplay_id) and is_list(changed_dependencies) do
    store.repo
    |> Analysis.affected_records(screenplay_id, normalize(changed_dependencies))
    |> Enum.map(&Map.take(&1, ~w(subject_kind subject_id analysis_run_id)))
  end

  def persisted_dependents(_, _, _), do: []

  @doc "Turns current canonical target/evidence identities into durable dependency keys."
  def canonical_keys(values) when is_list(values) do
    values
    |> Enum.flat_map(&canonical_key/1)
    |> normalize()
  end

  def canonical_keys(_), do: []

  defp canonical_key(%{"kind" => kind, "id" => id}) when is_binary(kind) and is_binary(id),
    do: ["target:#{kind}:#{id}"]

  defp canonical_key(%{kind: kind, id: id}) when is_binary(kind) and is_binary(id),
    do: ["target:#{kind}:#{id}"]

  defp canonical_key(%{"evidence_id" => id}) when is_binary(id), do: ["evidence:#{id}"]
  defp canonical_key(%{evidence_id: id}) when is_binary(id), do: ["evidence:#{id}"]
  defp canonical_key(value) when is_binary(value), do: [value]
  defp canonical_key(_), do: []

  defp normalize(values),
    do: values |> Enum.map(&to_string/1) |> Enum.uniq() |> Enum.sort()
end
