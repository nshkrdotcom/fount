defmodule Fount.Observe.Context.Quantity do
  @moduledoc "Neutral measurement context value; interpretation and acquisition remain outside this leaf type."
  defstruct [:value, :unit]
  @type t :: %__MODULE__{}
end
