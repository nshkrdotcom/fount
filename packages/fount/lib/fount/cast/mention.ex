defmodule Fount.Cast.Mention do
  @moduledoc "Evidence that an exact element-relative byte span may denote a cast character."

  @enforce_keys [:id, :element_id, :role, :status, :surface, :byte_start, :byte_end]
  defstruct [
    :id,
    :element_id,
    :character_id,
    :role,
    :status,
    :surface,
    :byte_start,
    :byte_end,
    :model_revision_id,
    :producer,
    :confidence,
    candidate_ids: []
  ]

  @type t :: %__MODULE__{}
end
