defmodule Fount.Intelligence.Reader.Snapshot do
  @moduledoc "Immutable presentation-relative Reader state after one visible screenplay element."
  @enforce_keys [:point, :state]
  defstruct [:point, :state, event_ids: []]
  @type t :: %__MODULE__{}
end
