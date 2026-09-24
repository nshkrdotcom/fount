defmodule Fount.Diagnostic do
  @moduledoc "Structured parser, validator, adapter, and analysis diagnostic."

  @enforce_keys [:severity, :code, :message]
  defstruct [:severity, :code, :message, :span, :node_id, :details]

  @type severity :: :info | :warning | :error
  @type t :: %__MODULE__{
          severity: severity(),
          code: atom(),
          message: String.t(),
          span: Fount.Source.Span.t() | nil,
          node_id: String.t() | nil,
          details: map() | nil
        }
end
