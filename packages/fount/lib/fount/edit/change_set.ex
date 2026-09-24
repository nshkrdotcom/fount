defmodule Fount.Edit.ChangeSet do
  @moduledoc """
  Auditable result of one edit transaction.

  Patch offsets are authoritative within each `Fount.Edit.Step`. Source and identity
  snapshots are captured for exact in-memory undo/redo without reverse-patch guesses.
  """

  @enforce_keys [:before_revision, :after_revision, :operations]
  defstruct [
    :before_revision,
    :after_revision,
    :operations,
    :steps,
    :patches,
    :affected_node_ids,
    :diagnostics,
    :inverse_source,
    :inverse_identity_anchors,
    :inverse_annotations,
    :forward_source,
    :forward_identity_anchors,
    :forward_annotations
  ]

  @type t :: %__MODULE__{}
end
