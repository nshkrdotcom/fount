defmodule Fount.Semantics.Mention do
  @moduledoc "Source-backed mention of a semantic entity."

  @enforce_keys [:id, :entity_id, :node_id, :text]
  defstruct [:id, :entity_id, :node_id, :text, :span, :role, :confidence]

  @type t :: %__MODULE__{
          id: String.t(),
          entity_id: String.t(),
          node_id: String.t(),
          text: String.t(),
          span: Fount.Source.Span.t() | nil,
          role: atom() | String.t() | nil,
          confidence: number() | nil
        }
end
