defmodule Fount.Observe.Context.EntityRef do
  @moduledoc "Neutral measurement context value; interpretation and acquisition remain outside this leaf type."
  defstruct [:id, :kind]
  @type t :: %__MODULE__{}
end
