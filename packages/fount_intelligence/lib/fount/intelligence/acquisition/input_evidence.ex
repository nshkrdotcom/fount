defmodule Fount.Intelligence.Acquisition.InputEvidence do
  @moduledoc false

  def resolve(_model, %{"evidence" => evidence}) when is_list(evidence), do: {:ok, evidence}

  def resolve(model, input) do
    with {:ok, units} <- Fount.Selection.select(model, %{"whole_screenplay" => true}) do
      resolve_units(units, input)
    end
  end

  defp resolve_units(units, input) do
    registry = units |> Fount.Selection.evidence() |> Map.new(&{&1["evidence_id"], &1})

    ids =
      references(input["state"]) ++
        if(Map.has_key?(registry, input["id"]), do: [input["id"]], else: [])

    Enum.reduce_while(Enum.uniq(ids), {:ok, []}, fn id, {:ok, found} ->
      case registry[id] do
        nil -> {:halt, {:error, :unknown_input_evidence}}
        source -> {:cont, {:ok, found ++ [source]}}
      end
    end)
  end

  defp references(map) when is_map(map) do
    Enum.flat_map(map, fn
      {"evidence_id", id} when is_binary(id) -> [id]
      {"evidence_ids", ids} when is_list(ids) -> Enum.filter(ids, &is_binary/1)
      {_, nested} -> references(nested)
    end)
  end

  defp references(list) when is_list(list), do: Enum.flat_map(list, &references/1)
  defp references(_), do: []
end
