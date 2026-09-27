defmodule Fount.Intelligence.Acquisition.Proposals do
  @moduledoc "Explicit host-owned proposal service. The shell validates data; it does not own an LLM client or generate canonical pages."
  alias Fount.Writing.Schema

  def complete(service, prompt, schema, validator, opts \\ []) do
    if is_function(service, 4) and is_binary(prompt) and is_map(schema) and
         is_function(validator, 1) do
      case service.(prompt, schema, validator, opts) do
        {:ok, value, traces} when is_map(value) and is_list(traces) ->
          validate_proposal(value, traces, schema, validator)

        {:error, reason, traces} when is_list(traces) ->
          {:error, neutral_error(reason), neutral_traces(traces)}

        _ ->
          {:error, :invalid_proposal_service_result, []}
      end
    else
      {:error, :missing_proposal_service, []}
    end
  rescue
    _ -> {:error, :proposal_service_failed, []}
  catch
    _, _ -> {:error, :proposal_service_failed, []}
  end

  defp validate_proposal(value, traces, schema, validator) do
    with :ok <- Schema.validate(schema, value), :ok <- validator.(value) do
      {:ok, value, neutral_traces(traces)}
    else
      {:error, reason} ->
        {:error, {:invalid_proposal, neutral_error(reason)}, neutral_traces(traces)}

      _ ->
        {:error, :invalid_validator_result, neutral_traces(traces)}
    end
  end

  defp neutral_error(reason) when is_atom(reason), do: reason
  defp neutral_error({kind, detail}) when is_atom(kind) and is_atom(detail), do: {kind, detail}
  defp neutral_error(_), do: :proposal_service_failed

  defp neutral_traces(traces) do
    Enum.map(traces, &neutral_trace/1)
  end

  defp neutral_trace(trace) when is_map(trace) and not is_struct(trace) do
    basic =
      Map.new(
        for key <- ~w(mode request_sha256 response_sha256 model response_id validation),
            value = trace[key],
            is_binary(value),
            do: {key, value}
      )

    case trace["usage"] do
      usage when is_map(usage) and not is_struct(usage) ->
        Map.put(basic, "usage", neutral_usage(usage))

      _ ->
        basic
    end
  end

  defp neutral_trace(_), do: %{}

  defp neutral_usage(usage) do
    Map.new(
      for key <- [:input_tokens, :output_tokens, :total_tokens],
          value = Map.get(usage, key, Map.get(usage, to_string(key))),
          is_number(value),
          do: {to_string(key), value}
    )
  end
end
