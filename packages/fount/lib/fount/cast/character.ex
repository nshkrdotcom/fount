defmodule Fount.Cast.Character do
  @moduledoc "Writer-authored character identity, independent of cue spelling."

  @enforce_keys [:id, :display_name]
  defstruct [:id, :display_name, :notes, aliases: [], attributes: %{}]

  @type t :: %__MODULE__{
          id: String.t(),
          display_name: String.t(),
          notes: String.t() | nil,
          aliases: [map()],
          attributes: map()
        }
end
