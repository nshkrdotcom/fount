defmodule Fount.Observe.ProviderResult do
  @moduledoc "One indexed, provider-neutral transport result; only adapters may construct it from SDK values."
  @enforce_keys [:batch_index]
  defstruct [:batch_index, :error, answers: %{}, metadata: %{}]
  @type t :: %__MODULE__{}
end
