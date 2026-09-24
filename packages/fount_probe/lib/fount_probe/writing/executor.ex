defmodule FountProbe.Writing.Executor do
  @moduledoc """
  Public System One batching with explicit zero-based response association.

  A request is `%{"id" => unique_string, "state" => utf8_json_string}`.
  The caller supplies questions made with public SDK constructors.
  """

  @defaults [
    max_concurrency: 4, max_pending: 8, ordered: false, on_error: :collect,
    task_timeout_ms: 120_000, attempt_timeout_ms: 60_000
  ]

  def evaluate(client, requests, questions, opts \\ []) do
    with :ok <- validate_requests(requests),
         {:ok, prepared} <- SystemOneSDK.prepare(questions) do
      states = Enum.map(requests, & &1["state"])
      stream_options = Keyword.merge(@defaults, opts)
      started = System.monotonic_time(:millisecond)
      result = SystemOneSDK.evaluate_stream(client, states, prepared, stream_options)

      case result do
        {:error, error} ->
          {:error, error}
        {:ok, stream} ->
          collect(stream, requests, prepared, started)
        stream ->
          collect(stream, requests, prepared, started)
      end
    end
  end

  def assemble(requests, results) do
    size = length(requests)

    Enum.reduce(results, {%{}, []}, fn item, {by_index, errors} ->
      case index(item) do
        n when is_integer(n) and n >= 0 and n < size ->
          if Map.has_key?(by_index, n) do
            {by_index, [%{"code" => "duplicate_batch_index", "batch_index" => n} | errors]}
          else
            {Map.put(by_index, n, item), errors}
          end
        _ ->
          {by_index, [%{"code" => "invalid_batch_index"} | errors]}
      end
    end)
    |> then(fn {by_index, errors} ->
      entries =
        requests
        |> Enum.with_index()
        |> Enum.map(fn {request, n} ->
          %{
            "input_id" => request["id"],
            "batch_index" => n,
            "result" => Map.get(by_index, n, {:error, :missing_response})
          }
        end)

      %{
        "entries" => entries,
        "errors" => Enum.reverse(errors),
        "requested" => size,
        "received" => map_size(by_index),
        "status" =>
          if(errors == [] and Enum.all?(entries, &match?({:ok, _}, &1["result"])),
            do: "complete", else: "partial")
      }
    end)
  end

  defp collect(stream, requests, prepared, started) do
    result = assemble(requests, Enum.to_list(stream))

    {:ok, Map.merge(result, %{
      "prepared_fingerprint" => SystemOneSDK.Prepared.fingerprint(prepared),
      "elapsed_ms" => System.monotonic_time(:millisecond) - started
    })}
  end

  defp index({:ok, response}), do: Map.get(response, :batch_index)
  defp index({:error, error}) when is_map(error) do
    details = Map.get(error, :details, %{}) || %{}
    Map.get(details, :batch_index) || Map.get(details, "batch_index")
  end
  defp index(_), do: nil

  defp validate_requests(requests) when is_list(requests) and requests != [] do
    valid =
      Enum.all?(requests, fn
        %{"id" => id, "state" => state} when is_binary(id) and is_binary(state) ->
          id != "" and String.valid?(state)
        _ -> false
      end)

    ids = if valid, do: Enum.map(requests, & &1["id"]), else: []
    cond do
      not valid -> {:error, :invalid_requests}
      length(ids) != length(Enum.uniq(ids)) -> {:error, :duplicate_request_ids}
      true -> :ok
    end
  end

  defp validate_requests(_), do: {:error, :empty_requests}
end
