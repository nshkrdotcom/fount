defmodule Fount.Observe.Executor do
  @moduledoc false
  alias Fount.Observe.{
    Association,
    Batch,
    Budget,
    Calibration,
    Cancellation,
    Context,
    Distribution,
    Error,
    Fingerprint,
    MeasurementResult,
    MeasurementSpec,
    Observation,
    OutputContract,
    Provider,
    ProviderCall,
    ProviderResult,
    Question,
    Registry,
    Request,
    Resources,
    TargetRef
  }

  alias Fount.Observe.Batch.Entry
  alias Fount.Writing.CanonicalJSON

  def evaluate(provider, requests, questions, opts \\ []) do
    with {:ok, plan} <- MeasurementSpec.compile(requests, questions, opts),
         do: execute(provider, requests, plan)
  end

  defp execute(provider, requests, plan) do
    started = System.monotonic_time(:millisecond)
    opts = plan.opts

    contexts =
      Context.prepare_many(Enum.map(requests, & &1.context), plan.lens["context_contract"])

    base =
      Map.merge(plan, %{
        run_id: opts[:run_id] || Fount.ID.v4(),
        contexts: Map.new(Enum.zip(Enum.map(requests, & &1.id), contexts))
      })

    preflight = Resources.estimate(requests, plan)

    {ready, completed} =
      requests
      |> Enum.with_index()
      |> Enum.reduce({[], %{}}, fn {request, index}, acc ->
        prepare_one(provider, request, index, base, acc)
      end)

    ready = Enum.reverse(ready)
    permitted = min(length(ready), opts[:max_provider_requests] || length(ready))
    granted = Budget.take(opts[:budget], permitted)
    {scheduled, over_budget} = Enum.split(ready, granted)

    completed =
      Enum.reduce(over_budget, completed, fn record, acc ->
        Map.put(acc, record.request.id, failed(record.request.id, Error.new(:budget_exhausted)))
      end)

    remaining = opts[:total_timeout_ms] - (System.monotonic_time(:millisecond) - started)
    dispatch_opts = Keyword.put(opts, :total_timeout_ms, max(remaining, 0))
    {finished, global_errors, batches} = dispatch(provider, scheduled, base, dispatch_opts)
    all = Map.merge(completed, finished)
    entries = Enum.map(requests, &Map.fetch!(all, &1.id))
    errors = global_errors ++ for(%Entry{error: %Error{} = error} <- entries, do: error)

    {:ok,
     %Batch{
       entries: entries,
       errors: errors,
       status: if(errors == [], do: :complete, else: :partial),
       requested: length(requests),
       scheduled: length(scheduled),
       received: Enum.count(entries, &(&1.status == :complete and not &1.cache_hit?)),
       cache_hits: Enum.count(entries, & &1.cache_hit?),
       provider_batches: batches,
       elapsed_ms: System.monotonic_time(:millisecond) - started,
       lens_asset: base.lens,
       measurement_spec_sha256: base.spec_hash,
       measurement_spec: base.specification,
       resource_usage: %{
         "preflight" => preflight,
         "actual" => Resources.actual(provider, entries, length(scheduled), opts[:budget])
       }
     }}
  end

  defp prepare_one(provider, request, index, base, {ready, done}) do
    case prepare(provider, request, index, base) do
      {:ok, record} ->
        case cached(record, base) do
          {:hit, results} ->
            {ready, Map.put(done, request.id, entry(record, results, base, true))}

          :miss ->
            {[record | ready], done}
        end

      {:error, error} ->
        {ready, Map.put(done, request.id, failed(request.id, error))}
    end
  end

  defp prepare(provider, request, index, base) do
    cond do
      Cancellation.cancelled?(base.opts[:cancellation]) ->
        {:error, Error.new(:provider_cancelled)}

      index >= base.opts[:max_states] ->
        {:error, Error.new(:budget_exhausted, nil, %{"reason" => "state_limit"})}

      not match?(%Provider{}, provider) ->
        {:error, Error.new(:provider_unconfigured)}

      request.projection_id != base.lens["projection"] ->
        {:error, Error.new(:invalid_projection)}

      true ->
        prepare_input(provider, request, base)
    end
  end

  defp prepare_input(provider, request, base) do
    with {:ok, _context} <- Map.fetch!(base.contexts, request.id),
         :ok <- Request.validate_envelope(request),
         bytes = Request.semantic_input(request),
         true <-
           byte_size(bytes) + byte_size(CanonicalJSON.encode!(base.specification)) <=
             base.opts[:max_context_bytes],
         {:ok, fingerprint} <- Fingerprint.request(provider, request, base.opts, base.run_id) do
      input_hash = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

      identity = %{
        "namespace" => base.opts[:privacy_namespace],
        "measurement_spec_sha256" => base.spec_hash,
        "input_sha256" => input_hash,
        "provider_fingerprint" => fingerprint,
        "semantic_execution_sha256" => base.execution_hash
      }

      cacheable =
        not is_nil(base.opts[:cache]) and
          (Fingerprint.stable?(fingerprint) or base.opts[:cache_policy] == :session)

      {:ok,
       %{
         request: request,
         input_hash: input_hash,
         fingerprint: fingerprint,
         key: CanonicalJSON.hash(identity),
         cacheable: cacheable
       }}
    else
      false -> {:error, Error.new(:state_too_large)}
      {:error, %Error{} = error} -> {:error, error}
      _ -> {:error, Error.new(:invalid_request)}
    end
  rescue
    _ -> {:error, Error.new(:invalid_request)}
  end

  defp dispatch(_provider, [], _base, _opts), do: {%{}, [], 0}

  defp dispatch(provider, records, base, opts) do
    requests = Enum.map(records, & &1.request)

    outcome =
      if opts[:total_timeout_ms] <= 0,
        do: {:error, Error.new(:provider_timeout)},
        else: ProviderCall.run(provider, requests, base.questions, opts)

    results =
      case outcome do
        {:ok, results} ->
          results

        {:error, error} ->
          Enum.with_index(requests)
          |> Enum.map(fn {_, index} ->
            %ProviderResult{batch_index: index, error: error}
          end)
      end

    {associated, errors} = Association.assemble(requests, results)
    by_id = Map.new(records, &{&1.request.id, &1})

    finished =
      Map.new(associated, fn {request, result} ->
        record = by_id[request.id]

        outcome =
          case measurement_results(record, result, base) do
            {:ok, measurements} ->
              store(record, measurements, base.opts)
              entry(record, measurements, base, false)

            {:error, error} ->
              failed(request.id, error)
          end

        {request.id, outcome}
      end)

    {finished, Enum.filter(errors, &is_nil(&1.request_id)), 1}
  end

  defp measurement_results(_record, %ProviderResult{error: %Error{} = error}, _base),
    do: {:error, error}

  defp measurement_results(record, result, base) do
    if MapSet.new(Map.keys(result.answers)) == MapSet.new(Enum.map(base.questions, &elem(&1, 0))) do
      Enum.reduce_while(
        base.questions,
        {:ok, []},
        &append_measurement(&1, &2, record, result, base)
      )
    else
      {:error, Error.new(:invalid_provider_response)}
    end
  rescue
    _ -> {:error, Error.new(:invalid_provider_response)}
  end

  defp append_measurement({key, q}, {:ok, acc}, record, result, base) do
    case measurement_result(record, result, base, key, q) do
      {:ok, measurement} -> {:cont, {:ok, acc ++ [measurement]}}
      error -> {:halt, error}
    end
  end

  defp measurement_result(record, result, base, key, q) do
    distribution = result.answers[key]
    fingerprint = Fingerprint.result(record.fingerprint, result.metadata)

    with true <- safe_provider_metadata?(result.metadata),
         true <- valid_distribution?(distribution, q, base.opts[:probability_tolerance] || 0.02),
         {:ok, calibration} <- Calibration.apply(distribution, base.calibration, fingerprint) do
      value = Distribution.to_map(distribution)

      measured = %MeasurementResult{
        id: "",
        value: value,
        distribution: distribution,
        output_contract_id: "observe.distribution",
        output_contract_sha256: Question.output_digest(q),
        measurement_spec_sha256: base.spec_hash,
        input_sha256: record.input_hash,
        provider_fingerprint: fingerprint,
        semantic_execution_sha256: base.execution_hash,
        normalized_raw: value,
        calibration: calibration,
        metadata: %{
          "question_key" => key,
          "provider" => result.metadata,
          "cache_policy" => to_string(base.opts[:cache_policy]),
          "cache_key" => record.key,
          "diagnostics" => Calibration.diagnostics(distribution.values)
        }
      }

      {:ok, %{measured | id: measurement_id(measured, record.key)}}
    else
      {:error, %Error{} = error} -> {:error, error}
      _ -> {:error, Error.new(:invalid_provider_response)}
    end
  end

  defp valid_distribution?(%Distribution{} = distribution, q, tolerance),
    do:
      Distribution.validate(distribution) == :ok and distribution.kind == q.kind and
        abs(Enum.sum(Enum.map(distribution.values, &elem(&1, 1))) - 1.0) <= tolerance + 1.0e-12 and
        Enum.map(distribution.values, &elem(&1, 0)) == Question.domain(q) and
        OutputContract.validate_value(
          Question.output_contract(q),
          Distribution.to_map(distribution)
        ) == :ok

  defp valid_distribution?(_, _, _), do: false

  defp measurement_id(value, key),
    do:
      "measurement-" <>
        CanonicalJSON.hash(%{
          "key" => key,
          "question" => value.metadata["question_key"],
          "value" => value.value,
          "provider_fingerprint" => value.provider_fingerprint,
          "calibration" => value.calibration
        })

  defp cached(%{cacheable: false}, _base), do: :miss

  defp cached(record, base) do
    {module, handle} = base.opts[:cache]

    case module.get(handle, record.key) do
      {:hit, values} when is_list(values) ->
        valid =
          length(values) == length(base.questions) and
            Enum.all?(Enum.zip(values, base.questions), &valid_cached?(&1, record, base))

        if valid, do: {:hit, values}, else: :miss

      _ ->
        :miss
    end
  rescue
    _ -> :miss
  catch
    :exit, _ -> :miss
  end

  defp valid_cached?({%MeasurementResult{} = value, {key, q}}, record, base) do
    valid_cached_metadata?(value, key, record) and
      valid_cached_identity?(value, q, record, base) and
      valid_cached_value?(value, q, record, base)
  end

  defp valid_cached?(_, _, _), do: false

  defp valid_cached_metadata?(value, key, record) do
    is_map(value.metadata) and
      Map.keys(value.metadata) -- ~w(question_key provider cache_policy cache_key diagnostics) ==
        [] and
      safe_provider_metadata?(value.metadata["provider"]) and
      Fingerprint.result(record.fingerprint, value.metadata["provider"]) ==
        value.provider_fingerprint and
      value.metadata["question_key"] == key and value.metadata["cache_key"] == record.key
  end

  defp valid_cached_identity?(value, q, record, base) do
    value.input_sha256 == record.input_hash and
      Fingerprint.matches?(value.provider_fingerprint, record.fingerprint) and
      value.measurement_spec_sha256 == base.spec_hash and
      value.semantic_execution_sha256 == base.execution_hash and
      value.output_contract_id == "observe.distribution" and
      value.output_contract_sha256 == Question.output_digest(q)
  end

  defp valid_cached_value?(value, q, record, base) do
    valid_distribution?(value.distribution, q, base.opts[:probability_tolerance] || 0.02) and
      value.value == Distribution.to_map(value.distribution) and
      value.normalized_raw == value.value and
      Calibration.apply(value.distribution, base.calibration, value.provider_fingerprint) ==
        {:ok, value.calibration} and
      value.metadata["diagnostics"] == Calibration.diagnostics(value.distribution.values) and
      value.id == measurement_id(value, record.key)
  end

  # Cached metadata is an untrusted payload too; native response bodies or
  # credentials must not re-enter observations through a custom cache.
  defp safe_provider_metadata?(metadata) when is_map(metadata) do
    allowed =
      ~w(provider model request_id prepared_fingerprint usage retries elapsed_ms runtime_elapsed_ms)

    Map.keys(metadata) -- allowed == [] and
      Enum.all?(Map.take(metadata, ~w(provider model request_id prepared_fingerprint)), fn {_,
                                                                                            value} ->
        is_nil(value) or (is_binary(value) and String.valid?(value) and byte_size(value) <= 256)
      end) and
      Enum.all?(Map.take(metadata, ~w(retries elapsed_ms runtime_elapsed_ms)), fn {_, value} ->
        is_nil(value) or (is_number(value) and value >= 0)
      end) and safe_usage?(Map.get(metadata, "usage", %{}))
  end

  defp safe_provider_metadata?(_), do: false

  defp safe_usage?(usage) when is_map(usage),
    do:
      Map.keys(usage) -- ~w(input_tokens output_tokens total_tokens) == [] and
        Enum.all?(usage, fn {_, value} -> is_number(value) and value >= 0 end)

  defp safe_usage?(_), do: false

  defp store(%{cacheable: false}, _, _), do: :ok

  defp store(record, results, opts) do
    {module, handle} = opts[:cache]
    module.put(handle, record.key, results)
    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp entry(record, results, base, hit?) do
    observations =
      Enum.map(results, fn result ->
        key = result.metadata["question_key"]

        identity = %{
          "run_id" => base.run_id,
          "request_id" => record.request.id,
          "question" => key,
          "target" => TargetRef.to_map(record.request.target),
          "result" => result.id
        }

        %Observation{
          id: "observation-" <> CanonicalJSON.hash(identity),
          kind: key,
          target: record.request.target,
          result: result,
          sensor_id: record.fingerprint["provider"],
          lens_id: base.lens["id"],
          lens_sha256: base.lens["sha256"],
          projection_id: record.request.projection_id,
          projection_sha256: Registry.projection_digest(record.request.projection_id),
          context_sha256: Context.hash(record.request.context),
          calibration_sha256: if(base.calibration, do: base.calibration["sha256"]),
          evidence: record.request.evidence,
          dependencies: Request.dependencies(record.request),
          provenance:
            Map.merge(record.request.provenance, %{
              "run_id" => base.run_id,
              "request_id" => record.request.id
            }),
          metadata: %{
            "cache_hit" => hit?,
            "claim_class" => "measurement_not_dramatic_verdict",
            "grounding" =>
              if(record.request.evidence == [],
                do: "semantic_input_only",
                else: "exact_source_evidence"
              )
          }
        }
      end)

    %Entry{
      request_id: record.request.id,
      status: :complete,
      observations: observations,
      cache_hit?: hit?
    }
  end

  defp failed(id, error),
    do: %Entry{request_id: id, status: :error, error: %{error | request_id: id}}
end
