defmodule FountRun.ApprovalAttempt do
  @moduledoc "Closed validation for durable approval-attempt identity and immutable payloads."

  alias Fount.Writing.{Approval, CanonicalJSON, Principal, Review}
  alias FountRun.ClosedMap

  @keys ~w(step_id decision_id parent_attempt_id candidate_id base_revision_id content_hash check_set_fingerprint packet packet_artifact_ref reviewer approver callback_operation_id fencing_token)

  def validate(attrs) do
    with {:ok, attrs} <- ClosedMap.normalize(attrs, @keys),
         {:ok, candidate_id} <- required_uuid(attrs, "candidate_id"),
         {:ok, base_revision_id} <- required_uuid(attrs, "base_revision_id"),
         :ok <- optional_uuid(attrs, "step_id"),
         :ok <- optional_uuid(attrs, "decision_id"),
         :ok <- optional_uuid(attrs, "parent_attempt_id"),
         {:ok, content_hash} <- hash(attrs, "content_hash"),
         {:ok, check_hash} <- hash(attrs, "check_set_fingerprint"),
         {:ok, packet} <- packet(attrs),
         {:ok, reviewer} <- principal(Map.get(attrs, "reviewer")),
         {:ok, approver} <- principal(Map.get(attrs, "approver")),
         {:ok, callback} <- required(attrs, "callback_operation_id"),
         fencing when is_integer(fencing) and fencing >= 0 <- Map.get(attrs, "fencing_token", 0) do
      {:ok,
       %{
         step_id: Map.get(attrs, "step_id"),
         decision_id: Map.get(attrs, "decision_id"),
         parent_attempt_id: Map.get(attrs, "parent_attempt_id"),
         candidate_id: candidate_id,
         base_revision_id: base_revision_id,
         content_hash: content_hash,
         check_set_fingerprint: check_hash,
         packet: packet,
         reviewer: reviewer,
         approver: approver,
         callback_operation_id: callback,
         fencing_token: fencing
       }}
    else
      _ -> {:error, :invalid_approval_attempt}
    end
  end

  def review_payload(%Review{} = review), do: {:ok, Review.to_map(review)}

  def review_payload(value) when is_map(value) do
    with {:ok, review} <- Review.from_map(value), do: {:ok, Review.to_map(review)}
  end

  def review_payload(_), do: {:error, :invalid_review_payload}

  def approval_payload(%Approval{} = approval), do: {:ok, Approval.to_map(approval)}

  def approval_payload(value) when is_map(value) do
    with {:ok, approval} <- Approval.from_map(value), do: {:ok, Approval.to_map(approval)}
  end

  def approval_payload(_), do: {:error, :invalid_approval_payload}

  def hash_payload(value), do: CanonicalJSON.hash(value)

  defp required(attrs, key) do
    value = Map.get(attrs, key)
    if ClosedMap.nonempty_string(value), do: {:ok, value}, else: {:error, {:invalid_field, key}}
  end

  defp required_uuid(attrs, key) do
    value = Map.get(attrs, key)
    if ClosedMap.uuid_string(value), do: {:ok, value}, else: {:error, {:invalid_field, key}}
  end

  defp optional_uuid(attrs, key) do
    case Map.get(attrs, key) do
      nil -> :ok
      value -> if ClosedMap.uuid_string(value), do: :ok, else: {:error, {:invalid_field, key}}
    end
  end

  defp hash(attrs, key) do
    with {:ok, value} <- required(attrs, key),
         true <- Regex.match?(~r/^[0-9a-f]{64}$/, value) do
      {:ok, value}
    else
      _ -> {:error, {:invalid_field, key}}
    end
  end

  defp principal(%Principal{} = principal), do: {:ok, principal}

  defp principal(value) when is_map(value) do
    with {:ok, value} <- ClosedMap.normalize(value, ~w(type id)), do: Principal.from_map(value)
  end

  defp principal(_), do: {:error, :invalid_principal}

  defp packet(attrs) do
    value = Map.get(attrs, "packet")
    ref = Map.get(attrs, "packet_artifact_ref")

    cond do
      not is_nil(value) and is_nil(ref) and ClosedMap.json?(value) -> {:ok, {:inline, value}}
      is_nil(value) and ClosedMap.nonempty_string(ref) -> {:ok, {:artifact, ref}}
      true -> {:error, :invalid_packet_binding}
    end
  end
end
