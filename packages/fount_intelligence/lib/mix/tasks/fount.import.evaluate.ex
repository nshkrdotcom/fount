defmodule Mix.Tasks.Fount.Import.Evaluate do
  @moduledoc "Evaluates an exported validated aggregate against gold labels and exact visible Fountain source, without inference."
  use Mix.Task
  alias Fount.Intelligence.ImportEvaluation

  @shortdoc "Offline import quality evaluation (--source, --gold, --result)"
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args, strict: [source: :string, gold: :string, result: :string])

    if rest != [] or invalid != [] or Enum.any?([:source, :gold, :result], &is_nil(opts[&1])),
      do:
        Mix.raise(
          "Usage: mix fount.import.evaluate --source VISIBLE.fountain --gold GOLD.json --result AGGREGATE.json"
        )

    source = File.read!(opts[:source])
    gold = opts[:gold] |> File.read!() |> Jason.decode!()
    result = opts[:result] |> File.read!() |> Jason.decode!()

    with :ok <- ImportEvaluation.verify_source(result, source),
         {:ok, report} <- ImportEvaluation.evaluate(result, gold) do
      Mix.shell().info(Jason.encode!(report, pretty: true))
    else
      {:error, reason} -> Mix.raise("Offline evaluation failed: #{reason}")
    end
  end
end
