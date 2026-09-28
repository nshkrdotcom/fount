defmodule FountRun.Step do
  @moduledoc "Closed storage shape for future worker steps; claiming/reclaim is Phase 03."
  alias Fount.Writing.CanonicalJSON
  alias FountRun.ClosedMap

  @stages ~w(intake investigate plan write check iterate decide deliver)
  @keys ~w(stage iteration branch_id input_revision_id input_candidate_id idempotency_key request)

  def validate(attrs) do
    with {:ok, attrs} <- ClosedMap.normalize(attrs, @keys),
         stage when stage in @stages <- Map.get(attrs, "stage"),
         iteration when is_integer(iteration) and iteration >= 0 <- Map.get(attrs, "iteration", 0),
         branch_id when is_binary(branch_id) and byte_size(branch_id) > 0 <-
           Map.get(attrs, "branch_id", "main"),
         :ok <- optional_uuid(attrs, "input_revision_id"),
         :ok <- optional_uuid(attrs, "input_candidate_id"),
         true <- ClosedMap.nonempty_string(Map.get(attrs, "idempotency_key")),
         request when is_map(request) <- Map.get(attrs, "request", %{}),
         true <- ClosedMap.json?(request) do
      {:ok,
       %{
         stage: stage,
         iteration: iteration,
         branch_id: branch_id,
         input_revision_id: attrs["input_revision_id"],
         input_candidate_id: attrs["input_candidate_id"],
         idempotency_key: attrs["idempotency_key"],
         request: request,
         request_fingerprint: CanonicalJSON.hash(request)
       }}
    else
      _ -> {:error, :invalid_step}
    end
  end

  defp optional_uuid(attrs, key) do
    case Map.get(attrs, key) do
      nil -> :ok
      value -> if ClosedMap.uuid_string(value), do: :ok, else: {:error, {:invalid_field, key}}
    end
  end
end
