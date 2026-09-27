defmodule Fount.Observe.Context.Turn do
  @moduledoc "Neutral measurement context value; interpretation and acquisition remain outside this leaf type."
  defstruct [:speaker, :text, channel: "dialogue"]
  @type t :: %__MODULE__{}
end
