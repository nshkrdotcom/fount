defmodule Fount.Observe.Context.Relation do
  @moduledoc "Neutral measurement context value; interpretation and acquisition remain outside this leaf type."
  defstruct [:subject, :predicate, :object, :strength]
  @type t :: %__MODULE__{}
end
