defmodule Fount.Observe.Recording do
  @moduledoc """
  Human, deterministic and imported measurements without fabricated model
  probabilities. Imports must match current semantic input and the caller's
  active output contract. Each import binds fresh current-revision evidence.
  No screenplay edits, callback execution or persistence occur here.
  """
  alias Fount.Observe.{
    Context,
    Error,
    MeasurementResult,
    Observation,
    OutputContract,
    Registry,
    Request,
    TargetRef
  }

  alias Fount.Writing.CanonicalJSON

  @empty_context %{"required" => %{}, "optional" => %{}, "allow_unknown" => false}
  @options [:contract, :origin, :producer, :producer_sha256, :kind, :context_contract]
  @payload ~w(value kind origin producer producer_sha256 output_contract context_contract input_sha256 projection_id projection_sha256 record_sha256)

  def record(request, value, opts \\ []) do
    with true <- Keyword.keyword?(opts) and Keyword.keys(opts) -- @options == [],
         true <- opts[:origin] in ["human", "deterministic"],
         true <- text?(opts[:producer]) and OutputContract.logical_id?(opts[:kind]),
         true <- is_nil(opts[:producer_sha256]) or digest?(opts[:producer_sha256]),
         :ok <- Request.validate_envelope(request),
         context_contract = Keyword.get(opts, :context_contract, @empty_context),
         :ok <- Context.validate(request.context, context_contract),
         :ok <- OutputContract.validate_value(opts[:contract], value),
         {:ok, bytes} <- CanonicalJSON.encode(value),
         true <- byte_size(bytes) <= 100_000 do
      payload = %{
        "value" => value,
        "kind" => opts[:kind],
        "origin" => opts[:origin],
        "producer" => opts[:producer],
        "producer_sha256" => opts[:producer_sha256],
        "output_contract" => opts[:contract],
        "context_contract" => context_contract,
        "input_sha256" => Request.input_hash(request),
        "projection_id" => request.projection_id,
        "projection_sha256" => Registry.projection_digest(request.projection_id)
      }

      payload = Map.put(payload, "record_sha256", CanonicalJSON.hash(payload))
      {:ok, observation(request, payload, opts[:origin])}
    else
      {:error, %Error{} = error} -> {:error, error}
      _ -> invalid()
    end
  rescue
    _ -> invalid()
  end

  def export(%Observation{result: %MeasurementResult{metadata: %{"recording" => payload}}}),
    do: payload

  @doc "Imports only the active recording contract, not historical shape generations."
  def import_record(request, payload, opts \\ []) do
    with true <- Keyword.keyword?(opts) and Keyword.keys(opts) -- [:contract] == [],
         true <- is_map(payload) and Enum.sort(Map.keys(payload)) == Enum.sort(@payload),
         :ok <- OutputContract.validate(payload["output_contract"]),
         :ok <- same_contract(opts[:contract], payload["output_contract"]),
         true <-
           payload["record_sha256"] == CanonicalJSON.hash(Map.delete(payload, "record_sha256")),
         true <- payload["input_sha256"] == Request.input_hash(request),
         true <-
           payload["projection_id"] == request.projection_id and
             payload["projection_sha256"] == Registry.projection_digest(request.projection_id),
         {:ok, _checked} <-
           record(request, payload["value"],
             contract: opts[:contract],
             kind: payload["kind"],
             origin: payload["origin"],
             producer: payload["producer"],
             producer_sha256: payload["producer_sha256"],
             context_contract: payload["context_contract"]
           ) do
      {:ok, observation(request, payload, "imported")}
    else
      {:error, %Error{} = error} -> {:error, error}
      _ -> invalid()
    end
  rescue
    _ -> invalid()
  end

  defp observation(request, payload, origin) do
    contract = payload["output_contract"]

    fingerprint = %{
      "provider" => payload["origin"],
      "producer" => payload["producer"],
      "producer_sha256" => payload["producer_sha256"],
      "stability" =>
        if(payload["origin"] == "deterministic" and digest?(payload["producer_sha256"]),
          do: "immutable_exact",
          else: "mutable_alias_or_unknown"
        )
    }

    specification = %{
      "kind" => payload["kind"],
      "producer" => fingerprint,
      "context_contract_sha256" => CanonicalJSON.hash(payload["context_contract"]),
      "projection_sha256" => Registry.projection_digest(request.projection_id),
      "output_contract_sha256" => contract["sha256"]
    }

    result = %MeasurementResult{
      id: "recording-" <> payload["record_sha256"],
      value: payload["value"],
      normalized_raw: payload["value"],
      distribution: nil,
      output_contract_id: contract["id"],
      output_contract_sha256: contract["sha256"],
      measurement_spec_sha256: CanonicalJSON.hash(specification),
      input_sha256: payload["input_sha256"],
      provider_fingerprint: fingerprint,
      semantic_execution_sha256: CanonicalJSON.hash(%{"operation" => "record_measurement"}),
      metadata: %{"recording" => payload, "claim_class" => payload["origin"] <> "_measurement"}
    }

    %Observation{
      id: "observation-" <> Fount.ID.v4(),
      kind: payload["kind"],
      target: request.target,
      result: result,
      sensor_id: payload["origin"],
      projection_id: request.projection_id,
      projection_sha256: Registry.projection_digest(request.projection_id),
      context_sha256: Context.hash(request.context),
      evidence: request.evidence,
      dependencies: Request.dependencies(request),
      provenance:
        Map.merge(request.provenance, %{
          "origin" => origin,
          "record_origin" => payload["origin"],
          "request_id" => request.id,
          "target" => TargetRef.to_map(request.target)
        }),
      metadata: %{
        "claim_class" => payload["origin"] <> "_measurement",
        "grounding" =>
          if(request.evidence == [], do: "semantic_input_only", else: "exact_source_evidence")
      }
    }
  end

  defp same_contract(a, b) do
    with :ok <- OutputContract.validate(a), true <- a == b do
      :ok
    else
      _ -> {:error, Error.new(:stale_contract)}
    end
  end

  defp text?(value),
    do:
      is_binary(value) and String.valid?(value) and String.trim(value) != "" and
        byte_size(value) <= 256

  defp digest?(value), do: is_binary(value) and Regex.match?(~r/^[0-9a-f]{64}$/, value)
  defp invalid, do: {:error, Error.new(:invalid_request)}
end
