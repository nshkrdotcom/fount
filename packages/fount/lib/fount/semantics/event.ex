defmodule Fount.Semantics.Event do
  @moduledoc "Interpreted event grounded in one or more screenplay nodes."

  @enforce_keys [:id, :type]
  defstruct [:id, :type, :participants, :evidence_node_ids, :attributes, :confidence, :provenance]

  @type t :: %__MODULE__{
          id: String.t(),
          type: atom() | String.t(),
          participants: map() | list() | nil,
          evidence_node_ids: [String.t()] | nil,
          attributes: map() | nil,
          confidence: number() | nil,
          provenance: Fount.Annotation.Provenance.t() | nil
        }
end
