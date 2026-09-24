defmodule Fount.Semantics.Relation do
  @moduledoc "Typed relationship between semantic entities with evidence."

  @enforce_keys [:id, :type, :from_id, :to_id]
  defstruct [:id, :type, :from_id, :to_id, :evidence_node_ids, :attributes, :confidence, :provenance]

  @type t :: %__MODULE__{
          id: String.t(),
          type: atom() | String.t(),
          from_id: String.t(),
          to_id: String.t(),
          evidence_node_ids: [String.t()] | nil,
          attributes: map() | nil,
          confidence: number() | nil,
          provenance: Fount.Annotation.Provenance.t() | nil
        }
end
