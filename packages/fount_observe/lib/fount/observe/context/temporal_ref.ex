defmodule Fount.Observe.Context.TemporalRef do
  @moduledoc "Neutral measurement context value; interpretation and acquisition remain outside this leaf type."
  defstruct [:point, relation: "unknown"]
  @type t :: %__MODULE__{}
end
