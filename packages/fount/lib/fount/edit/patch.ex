defmodule Fount.Edit.Patch do
  @moduledoc "Half-open source replacement."

  @enforce_keys [:byte_start, :byte_end, :replacement]
  defstruct [:byte_start, :byte_end, :replacement, :target_id, :kind]

  @type t :: %__MODULE__{
          byte_start: non_neg_integer(),
          byte_end: non_neg_integer(),
          replacement: binary(),
          target_id: String.t() | nil,
          kind: atom() | nil
        }

  @spec apply(binary(), [t()]) :: {:ok, binary()} | {:error, term()}
  def apply(source, patches) when is_binary(source) and is_list(patches) do
    with :ok <- validate(patches, byte_size(source)) do
      result =
        patches
        |> Enum.sort_by(& &1.byte_start, :desc)
        |> Enum.reduce(source, fn patch, acc ->
          prefix = binary_part(acc, 0, patch.byte_start)
          suffix = binary_part(acc, patch.byte_end, byte_size(acc) - patch.byte_end)
          prefix <> patch.replacement <> suffix
        end)

      {:ok, result}
    end
  end

  @spec translate_offset(non_neg_integer(), [t()]) :: non_neg_integer()
  def translate_offset(offset, patches) do
    Enum.reduce(patches, offset, fn patch, current ->
      delta = byte_size(patch.replacement) - (patch.byte_end - patch.byte_start)

      cond do
        patch.byte_end <= offset -> current + delta
        patch.byte_start <= offset and offset < patch.byte_end -> current - (offset - patch.byte_start)
        true -> current
      end
    end)
  end

  defp validate(patches, source_size) do
    sorted = Enum.sort_by(patches, & &1.byte_start)

    cond do
      Enum.any?(sorted, &(&1.byte_start < 0 or &1.byte_end < &1.byte_start or &1.byte_end > source_size)) ->
        {:error, :patch_out_of_range}

      overlapping?(sorted) ->
        {:error, :overlapping_patches}

      ambiguous_insertions?(sorted) ->
        {:error, :ambiguous_same_offset_insertions}

      true ->
        :ok
    end
  end

  defp overlapping?([left, right | rest]) do
    left.byte_end > right.byte_start or overlapping?([right | rest])
  end

  defp overlapping?(_), do: false

  defp ambiguous_insertions?([left, right | rest]) do
    both_insertions? =
      left.byte_start == left.byte_end and right.byte_start == right.byte_end and
        left.byte_start == right.byte_start

    both_insertions? or ambiguous_insertions?([right | rest])
  end

  defp ambiguous_insertions?(_), do: false
end
