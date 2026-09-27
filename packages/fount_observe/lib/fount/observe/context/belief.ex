defmodule Fount.Observe.Context.Belief do
  @moduledoc "Neutral measurement context value; interpretation and acquisition remain outside this leaf type."
  defstruct [:owner, :proposition, :probability, stance: "unknown"]
  @type t :: %__MODULE__{}
end
