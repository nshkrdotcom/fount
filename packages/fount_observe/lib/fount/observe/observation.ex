defmodule Fount.Observe.Observation do
  @moduledoc "Binds an immutable measurement to current target/evidence. A cache hit creates this binding anew."
  @enforce_keys [:id, :kind, :target, :result, :sensor_id]
  defstruct [
    :id,
    :kind,
    :target,
    :result,
    :sensor_id,
    :lens_id,
    :lens_sha256,
    :projection_id,
    :projection_sha256,
    :context_sha256,
    :calibration_sha256,
    :discourse_point,
    evidence: [],
    story_time_refs: [],
    dependencies: [],
    provenance: %{},
    metadata: %{}
  ]

  @type t :: %__MODULE__{}
end
