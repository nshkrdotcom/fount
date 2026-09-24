defmodule Fount.Annotation.Target do
  @moduledoc "Source-backed target for a derived annotation."
  @enforce_keys [:node_id]
  defstruct [:node_id, :span]
  @type t :: %__MODULE__{node_id: String.t(), span: Fount.Source.Span.t() | nil}
end
