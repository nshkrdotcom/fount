defmodule FountRun.StageRegistry do
  @moduledoc "Closed stage-handler registry for the durable headless screenplay pipeline."

  @stages ~w(intake investigate plan write check iterate decide deliver)

  def new(overrides \\ %{})

  def new(overrides) when is_map(overrides) do
    registry =
      Map.merge(
        %{
          "intake" => FountRun.PipelineHandler,
          "investigate" => FountRun.PipelineHandler,
          "plan" => FountRun.PipelineHandler,
          "write" => FountRun.WorkshopHandler,
          "check" => FountRun.PipelineHandler,
          "iterate" => FountRun.PipelineHandler
        },
        stringify_keys(overrides)
      )

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
