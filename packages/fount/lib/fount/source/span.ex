defmodule Fount.Source.Span do
  @moduledoc """
  Half-open byte range into an exact source binary.

  Byte offsets, not grapheme offsets, are the canonical coordinates because edits and
  lossless slicing must operate on the original bytes. Optional line/column values are
  conveniences for diagnostics only.
  """

  @enforce_keys [:byte_start, :byte_end]
  defstruct [:byte_start, :byte_end, :line_start, :column_start, :line_end, :column_end]

  @type t :: %__MODULE__{
          byte_start: non_neg_integer(),
          byte_end: non_neg_integer(),
          line_start: pos_integer() | nil,
          column_start: non_neg_integer() | nil,
          line_end: pos_integer() | nil,
          column_end: non_neg_integer() | nil
        }

  @spec new(non_neg_integer(), non_neg_integer(), keyword()) :: t()
  def new(byte_start, byte_end, opts \\ []) when byte_end >= byte_start do
    %__MODULE__{
      byte_start: byte_start,
      byte_end: byte_end,
      line_start: Keyword.get(opts, :line_start),
      column_start: Keyword.get(opts, :column_start),
      line_end: Keyword.get(opts, :line_end),
      column_end: Keyword.get(opts, :column_end)
    }
  end

  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{byte_start: first, byte_end: last}), do: last - first

  @spec slice(binary(), t()) :: binary()
  def slice(binary, %__MODULE__{} = span) when is_binary(binary) do
    binary_part(binary, span.byte_start, length(span))
  end

  @spec contains?(t(), non_neg_integer()) :: boolean()
  def contains?(%__MODULE__{} = span, offset),
    do: offset >= span.byte_start and offset < span.byte_end

  @spec overlaps?(t(), t()) :: boolean()
  def overlaps?(%__MODULE__{} = left, %__MODULE__{} = right),
    do: left.byte_start < right.byte_end and right.byte_start < left.byte_end

  @spec shift(t(), integer()) :: t()
  def shift(%__MODULE__{} = span, delta) do
    %{span | byte_start: span.byte_start + delta, byte_end: span.byte_end + delta}
  end

  @spec valid_for?(t(), binary()) :: boolean()
  def valid_for?(%__MODULE__{} = span, binary) when is_binary(binary) do
    span.byte_start >= 0 and span.byte_end >= span.byte_start and span.byte_end <= byte_size(binary)
  end
end
