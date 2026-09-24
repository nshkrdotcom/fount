defmodule Fount.Edit.Op do
  @moduledoc "Declarative screenplay edit operation."
  @enforce_keys [:kind]
  defstruct [:kind, :target, :value, :options]
  @type t :: %__MODULE__{kind: atom(), target: term(), value: term(), options: keyword() | nil}
end
