defmodule FountRun.StageRegistry do
  @moduledoc "Closed stage-handler registry. Phase 03 exposes only handlers that actually exist."

  @stages ~w(intake investigate plan write check iterate decide deliver)

  def new(overrides \\ %{})

  def new(overrides) when is_map(overrides) do
    registry = Map.merge(%{"write" => FountRun.WorkshopHandler}, stringify_keys(overrides))

    with true <- Enum.all?(Map.keys(registry), &(&1 in @stages)),
         true <- Enum.all?(registry, fn {_stage, handler} -> handler?(handler) end) do
      {:ok, registry}
    else
      _ -> {:error, :invalid_stage_registry}
    end
  end

  def new(_), do: {:error, :invalid_stage_registry}

  def fetch(registry, stage) when is_map(registry) and stage in @stages do
    case Map.fetch(registry, stage) do
      {:ok, handler} -> {:ok, handler}
      :error -> {:error, {:stage_handler_unavailable, stage}}
    end
  end

  def fetch(_, stage), do: {:error, {:invalid_stage, stage}}

  defp handler?(handler) when is_atom(handler),
    do: Code.ensure_loaded?(handler) and function_exported?(handler, :execute, 2)

  defp handler?(_), do: false

  defp stringify_keys(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
end
