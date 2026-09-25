defmodule FountProbe.StrategyContrast do
  @moduledoc "Compares dramatic mechanisms without naming a best draft."
  def run(model, params, clients, opts \\ []) do
    strategies = params["strategies"]

    if not is_list(strategies) or length(strategies) not in 2..5 do
      {:error, :two_to_five_strategies_required}
    else
      pairs =
        for {a, i} <- Enum.with_index(strategies),
            {b, j} <- Enum.with_index(strategies),
            i < j,
            do: {a, b}

      inputs =
        Enum.map(pairs, fn {a, b} ->
          %{
            "id" => a["id"] <> ":" <> b["id"],
            "state" => %{"brief" => params["brief"], "approach_a" => a, "approach_b" => b}
          }
        end)

      questions = [
        different:
          SystemOneSDK.noul(
            "Do the approaches change the causal route, character choice, source of resistance or disclosure in materially different ways, rather than paraphrasing?"
          )
      ]

      with {:ok, result} <-
             FountProbe.Jev.evaluate(
               clients[:system_one],
               inputs,
               questions,
               Keyword.put_new(opts, :profile_id, "strategy_contrast")
             ) do
        {:ok,
         FountProbe.Report.new(model, "strategy_contrast", params, %{
           status: result["status"],
           data: %{"pairs" => result["entries"], "ranking" => nil},
           provenance: result
         })}
      end
    end
  end
end
