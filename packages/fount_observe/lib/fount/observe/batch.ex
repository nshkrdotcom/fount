defmodule Fount.Observe.Batch do
  @moduledoc "A request-ordered acquisition result; partial coverage and actual state counts are explicit."
  defstruct entries: [],
            errors: [],
            status: :complete,
            requested: 0,
            scheduled: 0,
            received: 0,
            cache_hits: 0,
            elapsed_ms: 0,
            lens_asset: nil,
            measurement_spec_sha256: nil,
            measurement_spec: %{},
            provider_batches: 0,
            resource_usage: %{}

  @type t :: %__MODULE__{}
end

defmodule Fount.Observe.Batch.Entry do
  @moduledoc "One request outcome. Failed acquisition has no negative or fabricated observation."
  @enforce_keys [:request_id, :status]
  defstruct [:request_id, :status, :error, observations: [], cache_hit?: false]
  @type t :: %__MODULE__{}
end
