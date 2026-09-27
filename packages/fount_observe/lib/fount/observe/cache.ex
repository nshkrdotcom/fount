defmodule Fount.Observe.Cache do
  @moduledoc "L1 stores immutable MeasurementResults, never current-revision Observations. Adapters are trusted host code."
  @callback get(term(), String.t()) :: :miss | {:hit, [Fount.Observe.MeasurementResult.t()]}
  @callback put(term(), String.t(), [Fount.Observe.MeasurementResult.t()]) :: :ok
end
