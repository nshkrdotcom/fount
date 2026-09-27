defmodule Fount.Intelligence.Persistence.MeasurementCache do
  @moduledoc """
  Durable L2 adapter for `Fount.Observe.Cache`.

  An optional existing L1 cache may front the database. The durable store is
  privacy-namespaced and contains only immutable MeasurementResults. Observe
  still validates every cache hit before creating a fresh Observation.
  """

  @behaviour Fount.Observe.Cache

  alias Fount.Observe.{Distribution, MeasurementResult}
  alias Fount.Persistence.Analysis

  @impl true
  def get(handle, key) do
    case l1_get(handle, key) do
      {:hit, values} ->
        {:hit, values}

      :miss ->
        case Analysis.cache_get(handle.repo, handle.privacy_namespace, key) do
          {:hit, payloads} ->
            with {:ok, values} <- decode_many(payloads) do
              _ = l1_put(handle, key, values)
              {:hit, values}
            else
              _ -> :miss
            end

          :miss ->
            :miss
        end
    end
  rescue
    _ -> :miss
  catch
    :exit, _ -> :miss
  end

  @impl true
  def put(handle, key, results) when is_list(results) do
    _ = l1_put(handle, key, results)

    _ = Analysis.cache_put(handle.repo, handle.privacy_namespace, key, results)
    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp l1_get(%{l1: {module, cache}}, key) when is_atom(module) do
    case module.get(cache, key) do
      {:hit, values} when is_list(values) -> {:hit, values}
      _ -> :miss
    end
  rescue
    _ -> :miss
  catch
    :exit, _ -> :miss
  end

  defp l1_get(_handle, _key), do: :miss

  defp l1_put(%{l1: {module, cache}}, key, values) when is_atom(module) do
    module.put(cache, key, values)
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp l1_put(_handle, _key, _values), do: :ok

  defp decode_many(payloads) do
    Enum.reduce_while(payloads, {:ok, []}, fn payload, {:ok, acc} ->
      case decode(payload) do
        {:ok, result} -> {:cont, {:ok, acc ++ [result]}}
        error -> {:halt, error}
      end
    end)
  end

  defp decode(payload) when is_map(payload) do
    with {:ok, distribution} <- distribution(payload["distribution"]),
         true <- is_map(payload["provider_fingerprint"]),
         true <- is_map(payload["metadata"]) do
      {:ok,
       %MeasurementResult{
         id: payload["id"],
         value: payload["value"],
         distribution: distribution,
         output_contract_id: payload["output_contract_id"],
         output_contract_sha256: payload["output_contract_sha256"],
         measurement_spec_sha256: payload["measurement_spec_sha256"],
         input_sha256: payload["input_sha256"],
         provider_fingerprint: payload["provider_fingerprint"],
         semantic_execution_sha256: payload["semantic_execution_sha256"],
         calibration: payload["calibration"],
         normalized_raw: payload["normalized_raw"],
         metadata: payload["metadata"]
       }}
    else
      _ -> {:error, :invalid_durable_measurement}
    end
  rescue
    _ -> {:error, :invalid_durable_measurement}
  end

  defp decode(_), do: {:error, :invalid_durable_measurement}

  defp distribution(%{"kind" => kind, "values" => values} = payload)
       when kind in ["noul", "choice", "score"] and is_list(values) do
    pairs =
      Enum.map(values, fn
        [key, value] when is_binary(key) and is_number(value) -> {key, value}
        {key, value} when is_binary(key) and is_number(value) -> {key, value}
        _ -> :invalid
      end)

    if :invalid in pairs do
      {:error, :invalid_distribution}
    else
      value = %Distribution{
        kind: String.to_existing_atom(kind),
        values: pairs,
        selected: payload["selected"],
        scalar: payload["scalar"],
        confidence: payload["confidence"],
        labels: payload["labels"] || []
      }

      if Distribution.validate(value) == :ok,
        do: {:ok, value},
        else: {:error, :invalid_distribution}
    end
  rescue
    _ -> {:error, :invalid_distribution}
  end

  defp distribution(_), do: {:error, :invalid_distribution}
end
