defmodule FountRun.Attempt do
  @moduledoc "Closed validation for durable step-attempt storage; execution/recovery policy is Phase 03."

  alias FountRun.ClosedMap

  @start_keys ~w(step_id attempt_number fencing_token)
  @finish_keys ~w(outcome redacted_error provider_request_id)
  @terminal ~w(succeeded failed unknown cancelled fenced)

  def start(attrs) do
    with {:ok, attrs} <- ClosedMap.normalize(attrs, @start_keys),
         step_id when is_binary(step_id) <- Map.get(attrs, "step_id"),
         true <- ClosedMap.uuid_string(step_id),
         attempt_number when is_integer(attempt_number) and attempt_number > 0 <-
           Map.get(attrs, "attempt_number"),
         fencing_token when is_integer(fencing_token) and fencing_token >= 0 <-
           Map.get(attrs, "fencing_token") do
      {:ok,
       %{
         step_id: step_id,
         attempt_number: attempt_number,
         fencing_token: fencing_token
       }}
    else
      _ -> {:error, :invalid_attempt}
    end
  end

  def finish(attrs) do
    with {:ok, attrs} <- ClosedMap.normalize(attrs, @finish_keys),
         outcome when outcome in @terminal <- Map.get(attrs, "outcome"),
         :ok <- optional_error(Map.get(attrs, "redacted_error")),
         :ok <- optional_string(Map.get(attrs, "provider_request_id")) do
      {:ok,
       %{
         outcome: outcome,
         redacted_error: Map.get(attrs, "redacted_error"),
         provider_request_id: Map.get(attrs, "provider_request_id")
       }}
    else
      _ -> {:error, :invalid_attempt_result}
    end
  end

  defp optional_error(nil), do: :ok

  defp optional_error(value) when is_map(value),
    do: if(ClosedMap.json?(value), do: :ok, else: {:error, :invalid_error})

  defp optional_error(_), do: {:error, :invalid_error}

  defp optional_string(nil), do: :ok

  defp optional_string(value),
    do: if(ClosedMap.nonempty_string(value), do: :ok, else: {:error, :invalid_string})
end
