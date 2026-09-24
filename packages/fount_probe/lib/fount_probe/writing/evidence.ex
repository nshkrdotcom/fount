defmodule FountProbe.Writing.Evidence do
  @moduledoc """
  Exact revision-aware evidence registry validation.

  The supplied resolver is a trusted caller function, not model-controlled code:
  `(screenplay_id, revision_id, target) -> {:ok, current_text} | {:error, reason}`.
  """

  alias Fount.Writing.UTF8Span

  def validate(entries, resolver) when is_list(entries) and is_function(resolver, 3) do
    ids = Enum.map(entries, fn entry ->
      if is_map(entry), do: Map.get(entry, "evidence_id"), else: nil
    end)

    cond do
      Enum.any?(ids, &(not is_binary(&1) or &1 == "")) ->
        {:error, :invalid_evidence_id}
      length(ids) != length(Enum.uniq(ids)) ->
        {:error, :duplicate_evidence_ids}
      true ->
        Enum.reduce_while(entries, {:ok, %{}}, fn entry, {:ok, registry} ->
          case validate_entry(entry, resolver) do
            :ok -> {:cont, {:ok, Map.put(registry, entry["evidence_id"], entry)}}
            {:error, reason} -> {:halt, {:error, {entry["evidence_id"], reason}}}
          end
        end)
    end
  end

  def validate(_, _), do: {:error, :invalid_evidence_registry}

  def citations(ids, registry) when is_list(ids) and is_map(registry) do
    missing = Enum.reject(ids, &Map.has_key?(registry, &1))
    if missing == [], do: :ok, else: {:error, {:uninspected_citations, missing}}
  end

  defp validate_entry(%{
         "screenplay_id" => screenplay,
         "revision_id" => revision,
         "target" => %{"kind" => kind, "id" => id} = target,
         "excerpt" => excerpt
       }, resolver)
       when is_binary(screenplay) and is_binary(revision) and is_binary(id) and is_binary(excerpt) do
    with {:ok, text} <- resolver.(screenplay, revision, target) do
      case Map.get(target, "span") do
        nil -> if(text == excerpt, do: :ok, else: {:error, :excerpt_mismatch})
        span when kind == "element" -> UTF8Span.verify(text, span, excerpt)
        _ -> {:error, :span_requires_element}
      end
    end
  end

  defp validate_entry(_, _), do: {:error, :invalid_evidence_reference}
end
