defmodule Fount.Source do
  @moduledoc "Exact source payload and byte-preserving line index."

  alias Fount.Source.Line
  alias Fount.Source.Span

  @enforce_keys [:format, :raw, :lines]
  defstruct [:format, :raw, :lines, :path, :valid_utf8?, :newline_style]

  @type format :: :fountain | :fdx | :json | atom()
  @type t :: %__MODULE__{
          format: format(),
          raw: binary(),
          lines: [Line.t()],
          path: String.t() | nil,
          valid_utf8?: boolean(),
          newline_style: :lf | :crlf | :cr | :mixed | :none
        }

  @spec slice(t(), Span.t()) :: binary()
  def slice(%__MODULE__{raw: raw}, span), do: Span.slice(raw, span)
end
