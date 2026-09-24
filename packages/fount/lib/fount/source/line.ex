defmodule Fount.Source.Line do
  @moduledoc "Exact source line, including its original line terminator."

  alias Fount.Source.Span

  @enforce_keys [:number, :content, :eol, :span, :content_span]
  defstruct [:number, :content, :eol, :span, :content_span]

  @type t :: %__MODULE__{
          number: pos_integer(),
          content: binary(),
          eol: binary(),
          span: Span.t(),
          content_span: Span.t()
        }

  @spec raw(t()) :: binary()
  def raw(%__MODULE__{content: content, eol: eol}), do: content <> eol

  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{content: ""}), do: true
  def empty?(%__MODULE__{}), do: false

  @doc "A whitespace-only line is not structurally empty in Fountain; two spaces can be intentional dialogue whitespace."
  @spec whitespace_only?(t()) :: boolean()
  def whitespace_only?(%__MODULE__{content: content}) do
    content != "" and String.valid?(content) and String.trim(content) == ""
  end
end
