defmodule Fount.Edit.Step do
  @moduledoc "One operation applied against one concrete revision; patch coordinates are relative to `before_revision`."

  @enforce_keys [:before_revision, :after_revision, :operation, :patches]
  defstruct [:before_revision, :after_revision, :operation, :patches, :affected_node_ids]

  @type t :: %__MODULE__{
          before_revision: String.t(),
          after_revision: String.t(),
          operation: Fount.Edit.Op.t(),
          patches: [Fount.Edit.Patch.t()],
          affected_node_ids: [String.t()]
        }
end
