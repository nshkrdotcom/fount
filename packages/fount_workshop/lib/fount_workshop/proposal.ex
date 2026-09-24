defmodule FountWorkshop.Proposal do
  @moduledoc "Decodes bounded model proposals into existing Fount edit operations."

  alias Fount.Edit

  @enforce_keys [:base_revision, :operations]
  defstruct [:base_revision, :operations, :inference]

  @type t :: %__MODULE__{}

  @spec response_format() :: Inference.ResponseFormat.t()
  def response_format do
    {:json_schema,
     %{
       name: "screenplay_edit",
       strict: true,
       schema: %{
         "type" => "object",
         "properties" => %{
           "operations" => %{
             "type" => "array",
             "items" => %{
               "type" => "object",
               "properties" => %{
                 "kind" => %{"type" => "string"},
                 "target" => %{"type" => "string"},
                 "value" => %{"type" => "string"}
               },
               "required" => ["kind", "target", "value"]
             }
           }
         },
         "required" => ["operations"]
       }
     }}
  end

  @spec request(map(), String.t()) :: String.t()
  def request(context, instruction) do
    """
    Revise the screenplay scene using only the listed IDs. Return JSON with an
    operations array. Each operation is {"kind":"replace_text","target":ID,"value":TEXT}
    or {"kind":"set_scene_heading","target":SCENE_ID,"value":HEADING}.
    Do not include Markdown fences. Keep changes within the requested scene.

    Base revision: #{context.revision}
    Scene ID: #{context.scene_id}
    Elements: #{Jason.encode!(context.elements)}
    Selected scene content:\n#{context.source}

    Writer instruction: #{instruction}
    """
  end

  @spec decode(binary() | map(), map()) :: {:ok, t()} | {:error, term()}
  def decode(value, context) when is_binary(value) do
    with {:ok, parsed} <- Jason.decode(value), do: decode(parsed, context)
  end

  def decode(%{"operations" => operations}, context)
      when is_list(operations) and operations != [] do
    if length(operations) > 12 do
      {:error, :too_many_operations}
    else
      decode_operations(operations, context, [])
    end
  end

  def decode(_, _context), do: {:error, :invalid_proposal}

  defp decode_operations([], context, acc) do
    {:ok, %__MODULE__{base_revision: context.revision, operations: Enum.reverse(acc)}}
  end

  defp decode_operations([item | rest], context, acc) do
    case decode_operation(item, context) do
      {:ok, op} -> decode_operations(rest, context, [op | acc])
      error -> error
    end
  end

  defp decode_operation(
         %{"kind" => "replace_text", "target" => target, "value" => value},
         context
       )
       when is_binary(target) and is_binary(value) and byte_size(value) <= 8_000 do
    if Enum.any?(
         context.elements,
         &(&1.id == target and &1.type in [:action, :dialogue, :parenthetical])
       ) do
      {:ok, Edit.replace_text(target, value)}
    else
      {:error, {:invalid_target, target}}
    end
  end

  defp decode_operation(
         %{"kind" => "set_scene_heading", "target" => target, "value" => value},
         context
       )
       when is_binary(target) and is_binary(value) and byte_size(value) <= 200 do
    if target == context.scene_id,
      do: {:ok, Edit.set_scene_heading(target, value)},
      else: {:error, {:invalid_target, target}}
  end

  defp decode_operation(_, _context), do: {:error, :unsupported_operation}
end
