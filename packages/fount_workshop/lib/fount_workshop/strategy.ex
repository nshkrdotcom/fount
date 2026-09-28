defmodule FountWorkshop.Strategy do
  @moduledoc "Dramatic alternatives are stored separately from pages and can be materialized after writer selection."
  alias Fount.Writing.Schema
  alias FountWorkshop.Session
  alias FountWorkshop.Store
  alias FountWorkshop.Writing.Completion
  alias FountWorkshop.Writing.{Context, Intelligence}

  @strings ~w(id title premise_of_change dramatic_mechanism entry_state exit_state)
  @arrays ~w(beats preserves changes inventions consequences evidence_ids open_questions)
  @treatment_kinds ~w(action revelation relationship mixed)

  def generate(_model, request, context, services, opts \\ []) do
    if Map.has_key?(context, :investigation_strategies) do
      strategies = Enum.map(context.investigation_strategies, &normalize/1)
      {:ok, Intelligence.link_strategies(strategies, context), []}
    else
      count = request["alternatives"]
      treatments = get_in(request, ["options", "treatments"]) || []
      treatment_contract? = treatments != []

      schema = %{
        "type" => "object",
        "properties" => %{
          "strategies" => %{
            "type" => "array",
            "minItems" => count,
            "maxItems" => count,
            "items" => schema(treatment_contract?)
          }
        },
        "required" => ["strategies"],
        "additionalProperties" => false
      }

      validator =
        &validate_strategies(
          &1,
          schema,
          count,
          context.evidence,
          treatments,
          get_in(request, ["options", "allow_brief_departure"])
        )

      treatment_instruction =
        if treatment_contract? do
          " Each requested treatment is a binding route, not a label: return its treatment_id and mechanism_kind exactly, make the pages materially enact that instruction, name likely tradeoffs, preserve protected material, and disclose any brief departure. Requested treatments: " <>
            Jason.encode!(treatments) <> "."
        else
          ""
        end

      prompt =
        "You are developing choices for a professional spec screenplay. Create exactly #{count} genuinely different dramatic approaches to the writer's request. Change causal route, character choice, resistance, disclosure, physical action, or relationship strategy, not merely adjectives or paraphrase. No universal act formula, quality score, winner, or invented PDF savings. Describe actionable screenplay beats and concrete consequences. Disclose inventions. Nothing is accepted yet." <>
          treatment_instruction <>
          "\n" <>
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

  defp validate_strategies(value, schema, count, evidence, treatments, allow_departure) do
    with :ok <- Schema.validate(schema, value),
         true <-
           length(Enum.uniq_by(value["strategies"], & &1["id"])) == count or
             {:error, :duplicate_strategy_id},
         true <- valid_strategy_evidence?(value, evidence) or {:error, :uninspected_evidence},
         true <- distinct_strategies?(value["strategies"]) or {:error, :strategies_not_distinct} do
      treatment_match(value["strategies"], treatments, allow_departure)
    end
  end

  defp treatment_match(_strategies, [], _allow_departure), do: :ok

  defp treatment_match(strategies, treatments, allow_departure) do
    expected = Map.new(treatments, &{&1["id"], &1["mechanism_kind"]})
    actual = Map.new(strategies, &{&1["treatment_id"], &1["mechanism_kind"]})
    departures = Enum.map(strategies, &get_in(&1, ["brief_departure", "departed"]))

    cond do
      expected != actual ->
        {:error, :treatment_routes_not_honored}

      Enum.any?(strategies, &(not is_list(&1["tradeoffs"]) or &1["tradeoffs"] == [])) ->
        {:error, :treatment_tradeoff_required}

      allow_departure == false and Enum.any?(departures, &(&1 == true)) ->
        {:error, :brief_departure_not_permitted}

      true ->
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
          strategy["treatment_id"],
          strategy["mechanism_kind"],
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

  def schema(treatment_contract? \\ false) do
    props =
      Map.new(@strings, &{&1, %{"type" => "string"}})
      |> Map.merge(
        Map.new(@arrays, &{&1, %{"type" => "array", "items" => %{"type" => "string"}}})
      )
      |> Map.merge(%{
        "treatment_id" => %{"type" => ["string", "null"]},
        "mechanism_kind" => %{"type" => ["string", "null"], "enum" => @treatment_kinds ++ [nil]},
        "tradeoffs" => %{"type" => "array", "items" => %{"type" => "string"}},
        "brief_departure" => %{
          "type" => "object",
          "properties" => %{
            "departed" => %{"type" => "boolean"},
            "reason" => %{"type" => ["string", "null"]}
          },
          "required" => ["departed", "reason"],
          "additionalProperties" => false
        }
      })

    required =
      if treatment_contract?,
        do: @strings ++ @arrays ++ ~w(treatment_id mechanism_kind tradeoffs brief_departure),
        else: @strings ++ @arrays

    %{
      "type" => "object",
      "properties" => props,
      "required" => required,
      "additionalProperties" => false
    }
  end

  def normalize(value) do
    defaults =
      Map.new(@strings, &{&1, ""})
      |> Map.merge(Map.new(@arrays, &{&1, []}))
      |> Map.merge(%{
        "treatment_id" => nil,
        "mechanism_kind" => nil,
        "tradeoffs" => [],
        "brief_departure" => %{"departed" => false, "reason" => nil}
      })

    Map.merge(defaults, value)
  end

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
