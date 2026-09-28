defmodule FountRun.Budget do
  @moduledoc "Storage-level validation for usage reservations and settlements."
  alias FountRun.ClosedMap

  @reserve_keys ~w(operation_id step_id attempt_number session_id resource reserved_quantity reserved_cost_microunits currency knowledge_state)
  @settle_keys ~w(settled_quantity settled_cost_microunits provider_request_id knowledge_state reconciliation_state)

  def reservation(attrs) do
    with {:ok, attrs} <- ClosedMap.normalize(attrs, @reserve_keys),
         true <- ClosedMap.nonempty_string(Map.get(attrs, "operation_id")),
         true <- ClosedMap.nonempty_string(Map.get(attrs, "resource")),
         :ok <- optional_uuid(attrs, "step_id"),
         :ok <- optional_uuid(attrs, "session_id"),
         :ok <- optional_attempt(Map.get(attrs, "attempt_number")),
         q when is_integer(q) and q >= 0 <- Map.get(attrs, "reserved_quantity"),
         {:ok, cost, currency} <-
           cost(Map.get(attrs, "reserved_cost_microunits"), Map.get(attrs, "currency")),
         knowledge when knowledge in ["known", "estimated", "unknown"] <-
           Map.get(attrs, "knowledge_state", "known") do
      {:ok,
       %{
         operation_id: attrs["operation_id"],
         step_id: attrs["step_id"],
         attempt_number: attrs["attempt_number"],
         session_id: attrs["session_id"],
         resource: attrs["resource"],
         reserved_quantity: q,
         reserved_cost_microunits: cost,
         currency: currency,
         knowledge_state: knowledge
       }}
    else
      _ -> {:error, :invalid_usage_reservation}
    end
  end

  def settlement(attrs) do
    with {:ok, attrs} <- ClosedMap.normalize(attrs, @settle_keys),
         q when is_integer(q) and q >= 0 <- Map.get(attrs, "settled_quantity"),
         c when is_nil(c) or (is_integer(c) and c >= 0) <-
           Map.get(attrs, "settled_cost_microunits"),
         k when k in ["known", "estimated", "unknown"] <-
           Map.get(attrs, "knowledge_state", "known"),
         r when r in ["settled", "released", "unknown"] <-
           Map.get(attrs, "reconciliation_state", "settled") do
      {:ok,
       %{
         settled_quantity: q,
         settled_cost_microunits: c,
         provider_request_id: attrs["provider_request_id"],
         knowledge_state: k,
         reconciliation_state: r
       }}
    else
      _ -> {:error, :invalid_usage_settlement}
    end
  end

  defp cost(nil, nil), do: {:ok, nil, nil}

  defp cost(nil, currency) when is_binary(currency) do
    if Regex.match?(~r/^[A-Z]{3}$/, currency),
      do: {:ok, nil, currency},
      else: {:error, :invalid_currency}
  end

  defp cost(value, currency) when is_integer(value) and value >= 0 and is_binary(currency) do
    if Regex.match?(~r/^[A-Z]{3}$/, currency),
      do: {:ok, value, currency},
      else: {:error, :invalid_currency}
  end

  defp cost(_, _), do: {:error, :invalid_cost}

  defp optional_uuid(attrs, key) do
    case Map.get(attrs, key) do
      nil -> :ok
      value -> if ClosedMap.uuid_string(value), do: :ok, else: {:error, {:invalid_field, key}}
    end
  end

  defp optional_attempt(nil), do: :ok
  defp optional_attempt(value) when is_integer(value) and value > 0, do: :ok
  defp optional_attempt(_), do: {:error, :invalid_attempt_number}
end
