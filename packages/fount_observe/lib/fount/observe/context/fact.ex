defmodule Fount.Observe.Context.Fact do
  @moduledoc "Neutral measurement context value; interpretation and acquisition remain outside this leaf type."
  defstruct [:subject, :predicate, :object, stance: "asserted", evidence_ids: []]
  @type t :: %__MODULE__{}
end
