defmodule Fount.Observe.Provider do
  @moduledoc "Opaque installed-provider handle. Native SDK state is not an analysis contract and is never persisted."
  alias Fount.Observe.{Error, Registry}
  @enforce_keys [:sensor_id, :state, :fingerprint]
  @derive {Inspect, only: [:sensor_id]}
  defstruct [:sensor_id, :state, :fingerprint]
  @opaque t :: %__MODULE__{}

  @callback execute(
              term(),
              [Fount.Observe.Request.t()],
              [{String.t(), Fount.Observe.Question.t()}],
              keyword()
            ) ::
              {:ok, [Fount.Observe.ProviderResult.t()]} | {:error, Error.t()}
  @callback identity(term(), Fount.Observe.Request.t()) :: map()

  def identity(%__MODULE__{} = provider, request) do
    with {:ok, adapter} <- Registry.adapter(provider.sensor_id) do
      Map.merge(provider.fingerprint, adapter.identity(provider.state, request))
    end
  end

  def execute(%__MODULE__{} = provider, requests, questions, opts) do
    with {:ok, adapter} <- Registry.adapter(provider.sensor_id),
         do: adapter.execute(provider.state, requests, questions, opts)
  end
end
