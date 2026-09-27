defmodule Fount.Observe.Executor do
  @moduledoc false
  alias Fount.Observe.{
    Association,
    Batch,
    Budget,
    Cancellation,
    Context,
    Distribution,
    Error,
    EvidenceRef,
    Lens,
    MeasurementResult,
    Observation,
    Options,
    Provider,
    ProviderCall,
    ProviderResult,
    Question,
    Registry,
    Request,
    TargetRef
  }

  alias Fount.Observe.Batch.Entry
  alias Fount.Writing.CanonicalJSON

  def evaluate(provider, requests, questions, opts \\ []) do
    with {:ok, opts} <- Options.normalize(opts),
         {:ok, questions, lens} <- Lens.compile(questions, opts[:lens_id]),
         :ok <- request_ids(requests) do
      execute(provider, requests, questions, lens, opts)
    end
  end

  defp execute(provider, requests, questions, lens, opts) do
    started = System.monotonic_time(:millisecond)
    run_id = opts[:run_id] || Fount.ID.v4()

    specification = %{
      "questions" => Question.specifications(questions),
      "lens_sha256" => lens["sha256"],
      "output_contracts" =>
        Enum.map(questions, fn {key, q} ->
          %{"key" => key, "sha256" => Question.output_digest(q)}
        end),
      "projection_sha256" => Registry.projection_digest(lens["projection"])
    }

    spec_hash = CanonicalJSON.hash(specification)
    execution_hash = CanonicalJSON.hash(Options.semantic(opts))

    base = %{
      questions: questions,
      lens: lens,
      spec_hash: spec_hash,
      execution_hash: execution_hash,
      run_id: run_id
    }

    {ready, completed} =
      requests
      |> Enum.with_index()
      |> Enum.reduce({[], %{}}, fn {request, index}, acc ->
        prepare_one(provider, request, index, specification, base, opts, acc)
      end)

    granted = Budget.take(opts[:budget], length(ready))
    {scheduled, over_budget} = Enum.split(ready, granted)

    completed =
      Enum.reduce(over_budget, completed, fn record, acc ->
        Map.put(acc, record.request.id, failed(record.request.id, Error.new(:budget_exhausted)))
      end)

    {finished, global_errors, batches} = dispatch(provider, scheduled, base, opts)
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
       lens_asset: lens,
       measurement_spec_sha256: spec_hash,
       measurement_spec: specification
     }}
  end

  defp prepare_one(provider, request, index, specification, base, opts, {ready, done}) do
    case prepare(provider, request, index, specification, base, opts) do
      {:ok, record} ->
        case cached(record, base.questions, opts) do
          {:hit, results} ->
            {ready, Map.put(done, request.id, entry(record, results, base, true))}

          :miss ->
            {ready ++ [record], done}
        end

      {:error, error} ->
        {ready, Map.put(done, request.id, failed(request.id, error))}
    end
  end

  defp prepare(provider, request, index, specification, base, opts) do
    cond do
      Cancellation.cancelled?(opts[:cancellation]) ->
        {:error, Error.new(:provider_cancelled)}

      index >= opts[:max_states] ->
        {:error, Error.new(:budget_exhausted, nil, %{"reason" => "state_limit"})}

      not match?(%Provider{}, provider) ->
        {:error, Error.new(:provider_unconfigured)}

      request.projection_id != base.lens["projection"] ->
        {:error, Error.new(:invalid_projection)}

      true ->
        prepare_input(provider, request, specification, base, opts)
    end
  end

  defp prepare_input(provider, request, specification, base, opts) do
    with :ok <- Context.validate(request.context, base.lens["context_contract"]),
         :ok <- envelope(request),
         {:ok, bytes} <-
           CanonicalJSON.encode(%{
             "state" => request.input,
             "context" => Context.to_map(request.context)
           }),
         true <-
           byte_size(bytes) + byte_size(CanonicalJSON.encode!(specification)) <=
             opts[:max_context_bytes],
         fingerprint when is_map(fingerprint) <- Provider.identity(provider, request),
         {:ok, _} <- CanonicalJSON.encode(fingerprint) do
      input_hash = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

      identity = %{
        "namespace" => opts[:privacy_namespace],
        "measurement_spec_sha256" => base.spec_hash,
        "input_sha256" => input_hash,
        "provider_fingerprint" => fingerprint,
        "semantic_execution_sha256" => base.execution_hash
      }

      cacheable =
        not is_nil(opts[:cache]) and
          (fingerprint["stability"] in ~w(immutable_exact provider_stable) or
             opts[:cache_policy] == :session)

      {:ok,
       %{
         request: request,
         input_hash: input_hash,
         fingerprint: fingerprint,
         spec_hash: base.spec_hash,
         execution_hash: base.execution_hash,
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

  defp envelope(%Request{
         target: %TargetRef{} = target,
         evidence: evidence,
         provenance: provenance
       }) do
    valid =
      Enum.all?(
        [target.screenplay_id, target.revision_id, target.kind, target.id],
        &(is_binary(&1) and &1 != "")
      ) and
        is_list(evidence) and
        Enum.all?(evidence, fn
          %EvidenceRef{} = ref ->
            ref.screenplay_id == target.screenplay_id and ref.revision_id == target.revision_id

          _ ->
            false
        end) and match?({:ok, _}, CanonicalJSON.encode(provenance))

    if valid, do: :ok, else: {:error, Error.new(:invalid_target)}
  end

  defp envelope(_), do: {:error, Error.new(:invalid_target)}

  defp dispatch(_provider, [], _base, _opts), do: {%{}, [], 0}

  defp dispatch(provider, records, base, opts) do
    requests = Enum.map(records, & &1.request)

    results =
      case ProviderCall.run(provider, requests, base.questions, opts) do
        {:ok, results} ->
          results

        {:error, error} ->
          Enum.with_index(requests)
          |> Enum.map(fn {_, index} -> %ProviderResult{batch_index: index, error: error} end)
      end

    {associated, errors} = Association.assemble(requests, results)
    by_id = Map.new(records, &{&1.request.id, &1})

    finished =
      Map.new(associated, fn {request, result} ->
        record = Map.fetch!(by_id, request.id)

        outcome =
          case measurement_results(record, result, base, opts) do
            {:ok, measurements} ->
              store(record, measurements, opts)
              entry(record, measurements, base, false)

            {:error, error} ->
              failed(request.id, error)
          end

        {request.id, outcome}
      end)

    # Request-specific errors already live on entries; retain only unassociated failures here.
    global = Enum.filter(errors, &is_nil(&1.request_id))
    {finished, global, 1}
  end

  defp measurement_results(_record, %ProviderResult{error: %Error{} = error}, _base, _opts),
    do: {:error, error}

  defp measurement_results(record, result, base, opts) do
    expected = Enum.map(base.questions, &elem(&1, 0))

    if MapSet.new(Map.keys(result.answers)) == MapSet.new(expected) do
      Enum.reduce_while(base.questions, {:ok, []}, fn {key, q}, {:ok, acc} ->
        measurement_result(record, result, base, opts, key, q, acc)
      end)
    else
      {:error, Error.new(:invalid_provider_response)}
    end
  rescue
    _ -> {:error, Error.new(:invalid_provider_response)}
  end

  defp measurement_result(record, result, base, opts, key, q, acc) do
    distribution = result.answers[key]

    if valid_distribution?(distribution, q) do
      value = Distribution.to_map(distribution)
      content = %{"key" => record.key, "question" => key, "value" => value}

      measured = %MeasurementResult{
        id: "measurement-" <> CanonicalJSON.hash(content),
        value: value,
        distribution: distribution,
        output_contract_id: "observe.distribution",
        output_contract_sha256: Question.output_digest(q),
        measurement_spec_sha256: base.spec_hash,
        input_sha256: record.input_hash,
        provider_fingerprint: record.fingerprint,
        semantic_execution_sha256: base.execution_hash,
        normalized_raw: value,
        metadata: %{
          "question_key" => key,
          "provider" => result.metadata,
          "cache_policy" => to_string(opts[:cache_policy])
        }
      }

      {:cont, {:ok, acc ++ [measured]}}
    else
      {:halt, {:error, Error.new(:invalid_provider_response)}}
    end
  end

  defp valid_distribution?(%Distribution{} = d, q) do
    Distribution.validate(d) == :ok and d.kind == q.kind and
      Enum.map(d.values, &elem(&1, 0)) == Question.domain(q)
  end

  defp valid_distribution?(_, _), do: false

  defp cached(%{cacheable: false}, _questions, _opts), do: :miss

  defp cached(record, questions, opts) do
    {module, handle} = opts[:cache]

    case module.get(handle, record.key) do
      {:hit, values} when is_list(values) ->
        if valid_cache_values?(values, questions, record), do: {:hit, values}, else: :miss

      _ ->
        :miss
    end
  rescue
    _ -> :miss
  catch
    :exit, _ -> :miss
  end

  defp valid_cache_values?(values, questions, record) do
    length(values) == length(questions) and
      Enum.zip(values, questions) |> Enum.all?(&valid_cache_value?(&1, record))
  end

  defp valid_cache_value?({%MeasurementResult{} = value, {key, q}}, record) do
    value.metadata["question_key"] == key and value.input_sha256 == record.input_hash and
      value.provider_fingerprint == record.fingerprint and
      value.measurement_spec_sha256 == record.spec_hash and
      value.semantic_execution_sha256 == record.execution_hash and
      valid_cached_output?(value, key, q, record)
  end

  defp valid_cache_value?(_, _), do: false

  defp valid_cached_output?(value, key, q, record) do
    value.output_contract_id == "observe.distribution" and
      value.output_contract_sha256 == Question.output_digest(q) and
      valid_distribution?(value.distribution, q) and
      value.value == Distribution.to_map(value.distribution) and
      value.id ==
        "measurement-" <>
          CanonicalJSON.hash(%{
            "key" => record.key,
            "question" => key,
            "value" => value.value
          })
  end

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
          evidence: record.request.evidence,
          provenance:
            Map.merge(record.request.provenance, %{
              "run_id" => base.run_id,
              "request_id" => record.request.id
            }),
          metadata: %{
            "cache_hit" => hit?,
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

  defp request_ids(requests) when is_list(requests) do
    if Enum.all?(requests, &match?(%Request{}, &1)) do
      ids = Enum.map(requests, & &1.id)

      if Enum.all?(ids, &(is_binary(&1) and &1 != "")) and length(ids) == length(Enum.uniq(ids)),
        do: :ok,
        else: {:error, Error.at(:invalid_request, ["request_ids"])}
    else
      {:error, Error.at(:invalid_request, ["requests"])}
    end
  end

  defp request_ids(_), do: {:error, Error.at(:invalid_request, ["requests"])}
end
