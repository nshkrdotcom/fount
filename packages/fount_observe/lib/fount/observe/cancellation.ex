defmodule Fount.Observe.Cancellation do
  @moduledoc "Caller-owned cancellation token. Cancelled acquisition never supplies semantic evidence."
  @enforce_keys [:flag]
  defstruct [:flag]
  @type t :: %__MODULE__{}
  def new, do: %__MODULE__{flag: :atomics.new(1, signed: false)}
  def cancel(%__MODULE__{flag: flag}), do: :atomics.put(flag, 1, 1)
  def cancelled?(nil), do: false
  def cancelled?(%__MODULE__{flag: flag}), do: :atomics.get(flag, 1) == 1
end
