defmodule FountWorkshop.Strategy do
  @moduledoc "Dramatic alternatives are stored separately from pages and can be materialized after writer selection."
  alias Fount.Writing.Schema
  alias FountWorkshop.Session
  alias FountWorkshop.Store
  alias FountWorkshop.Writing.Completion
  alias FountWorkshop.Writing.{Context, Intelligence}
  @strings ~w(id title premise_of_change dramatic_mechanism entry_state exit_state)
  @arrays ~w(beats preserves changes inventions consequences evidence_ids open_questions)
  def generate(_model, request, context, services, opts \\ []) do
    if Map.has_key?(context, :investigation_strategies) do
      strategies = Enum.map(context.investigation_strategies, &normalize/1)
      {:ok, Intelligence.link_strategies(strategies, context), []}
    else
      count = request["alternatives"]

      schema = %{
        "type" => "object",
        "properties" => %{
          "strategies" => %{
            "type" => "array",
            "minItems" => count,
            "maxItems" => count,
            "items" => schema()
          }
        },
        "required" => ["strategies"],
        "additionalProperties" => false
      }

      validator = &validate_strategies(&1, schema, count, context.evidence)

      prompt =
        "You are developing choices for a professional spec screenplay. Create exactly #{count} genuinely different dramatic approaches to the writer's request. Change causal route, character choice, resistance, or disclosure, not merely adjectives. No universal act formula, quality score, winner, or invented PDF savings. Describe actionable screenplay beats and concrete consequences. Disclose inventions. Nothing is accepted yet.\n" <>
          Jason.encode!(Context.prompt_data(context.data, inspection_sample_limit: 4))

      with {:ok, value, traces} <-
             Completion.complete(
               services[:inference],
               prompt,
               schema,
               validator,
               Keyword.put(opts, :name, "fount_strategies")
             ) do
        {:ok, Intelligence.link_strategies(value["strategies"], context), traces}
      end
    end
  end

  defp validate_strategies(value, schema, count, evidence) do
    with :ok <- Schema.validate(schema, value),
         true <-
           length(Enum.uniq_by(value["strategies"], & &1["id"])) == count or
             {:error, :duplicate_strategy_id},
         true <- valid_strategy_evidence?(value, evidence) or {:error, :uninspected_evidence},
         true <- distinct_strategies?(value["strategies"]) or {:error, :strategies_not_distinct} do
      :ok
    end
  end

  defp valid_strategy_evidence?(value, evidence) do
    inspected = MapSet.new(evidence, & &1["evidence_id"])

    Enum.all?(
      Enum.flat_map(value["strategies"], & &1["evidence_ids"]),
      &MapSet.member?(inspected, &1)
    )
  end

  defp distinct_strategies?(strategies) do
    signatures =
      Enum.map(strategies, fn strategy ->
        [
          strategy["premise_of_change"],
          strategy["dramatic_mechanism"],
          Enum.sort(strategy["changes"] || []),
          Enum.sort(strategy["consequences"] || [])
        ]
        |> Jason.encode!()
        |> String.downcase()
      end)

    length(signatures) == length(Enum.uniq(signatures))
  end

  def schema do
    props =
      Map.new(@strings, &{&1, %{"type" => "string"}})
      |> Map.merge(
        Map.new(@arrays, &{&1, %{"type" => "array", "items" => %{"type" => "string"}}})
      )

    %{
      "type" => "object",
      "properties" => props,
      "required" => @strings ++ @arrays,
      "additionalProperties" => false
    }
  end

  def normalize(value),
    do: Map.merge(Map.new(@strings, &{&1, ""}) |> Map.merge(Map.new(@arrays, &{&1, []})), value)

  def materialize(session_id, strategy_ids, services, opts \\ []) do
    with {:ok, session} <- Store.call(services[:store], :session, [session_id]),
         true <-
           (is_list(strategy_ids) and strategy_ids != [] and
              Enum.all?(
                strategy_ids,
                &(&1 in Enum.map(session["strategies"], fn s -> s["id"] end))
              )) or {:error, :unknown_strategy} do
      Session.resume(session_id, services, Keyword.put(opts, :strategy_ids, strategy_ids))
    end
  end
end
