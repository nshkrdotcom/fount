defmodule Fount.IR.Script do
  @moduledoc "Canonical screenplay IR. Elements are flat; scenes/dialogue/outline are stable-ID views."

  @enforce_keys [:document_id, :elements]
  defstruct [
    :document_id,
    :title_page,
    :elements,
    :scenes,
    :dialogue_blocks,
    :outline,
    :metadata
  ]

  @type t :: %__MODULE__{}
end
