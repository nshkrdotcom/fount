defmodule FountWorkshop.Preview do
  @moduledoc "Immutable revision preview; acceptance persists its document only after a revision check."

  @enforce_keys [:document, :change_set, :base_revision, :source_diff, :semantic_diff]
  defstruct [
    :document,
    :change_set,
    :base_revision,
    :source_diff,
    :semantic_diff,
    :diagnostics,
    :inference
  ]

  @type t :: %__MODULE__{}
end
