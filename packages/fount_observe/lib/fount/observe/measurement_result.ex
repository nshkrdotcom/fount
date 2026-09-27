defmodule Fount.Observe.MeasurementResult do
  @moduledoc "Immutable reusable measurement, deliberately independent of screenplay revision and source spans."
  @enforce_keys [
    :id,
    :value,
    :distribution,
    :output_contract_id,
    :output_contract_sha256,
    :measurement_spec_sha256,
    :input_sha256,
    :provider_fingerprint,
    :semantic_execution_sha256
  ]
  defstruct [
    :id,
    :value,
    :distribution,
    :output_contract_id,
    :output_contract_sha256,
    :measurement_spec_sha256,
    :input_sha256,
    :provider_fingerprint,
    :semantic_execution_sha256,
    normalized_raw: nil,
    metadata: %{}
  ]

  @type t :: %__MODULE__{}
end
