defmodule Fount.Semantics.Entity do
  @moduledoc "Interpreted story-world entity, separate from literal screenplay cues/mentions."

  @enforce_keys [:id, :kind, :canonical_name]
  defstruct [:id, :kind, :canonical_name, aliases: [], attributes: %{}, provenance: nil]

  @type t :: %__MODULE__{
          id: String.t(),
          kind: atom() | String.t(),
          canonical_name: String.t(),
          aliases: [String.t()],
          attributes: map(),
          provenance: Fount.Annotation.Provenance.t() | nil
        }
end
