defmodule FountProbe.Dependencies do
  @moduledoc "Tests proposed setup/use edges, including alternative support in an actually ablated context."
  alias FountProbe.Jev
  alias FountProbe.Projection
  alias FountProbe.Report
  alias FountProbe.SavedRecords

  def run(model, params, clients, opts \\ []) do
    with {:ok, extracted} <-
           SavedRecords.resolve(
             model,
             params,
             clients,
             opts,
             ~w(events propositions props commitments),
             "Identify setups and later uses that may depend on them."
           ),
         {:ok, units} <- Projection.select(model, params["selection"]) do
      registry = Map.new(units, &{&1["evidence_id"], &1})
      records = extracted.data["records"]
      order = Map.new(Enum.with_index(model.ir.scenes), fn {s, n} -> {s.id, n} end)
      pairs = ordered_pairs(model, records, units, params["targets"])

      # Do not discard a semantic relationship merely for lacking common words.
      inputs =
        Enum.with_index(pairs, fn {a, b}, n ->
          %{
            "id" => "edge_#{n}",
            "state" => %{"a" => quoted(a, registry), "b" => quoted(b, registry)}
          }
        end)

      questions = [
        establishes:
          SystemOneSDK.noul(
            "Does A establish the object, ability, information or rule used by B?"
          ),
        enables:
          SystemOneSDK.noul(
            "Does the material in A make the event in B possible or motivate its choice?"
          ),
        purpose:
          SystemOneSDK.noul("Does A serve an immediate local dramatic purpose independent of B?"),
        relation:
          SystemOneSDK.choice("What best describes the supported relation from A to B?",
            cause: "Brings B about",
            enable: "Makes B possible",
            motivate: "Gives a reason for B",
            setup: "Prepares a reader for B",
            none: "No supported relation"
          )
      ]

      evaluate_pairs(model, params, clients, opts, %{
        extracted: extracted,
        units: units,
        registry: registry,
        records: records,
        order: order,
        pairs: pairs,
        inputs: inputs,
        questions: questions
      })
    end
  end

  defp evaluate_pairs(model, params, clients, opts, %{
         extracted: extracted,
         units: units,
         registry: registry,
         records: records,
         order: order,
         pairs: pairs,
         inputs: inputs,
         questions: questions
       }) do
    with {:ok, result} <-
           Jev.evaluate(
             clients[:system_one],
             inputs,
             questions,
             Keyword.put_new(opts, :profile_id, "dependencies")
           ) do
      alternative = alternative_support(params, clients, opts, pairs, units, order, registry)

      {alternative, errors} =
        case alternative do
          {:ok, a} ->
            {a, []}

          {:error, _} ->
            {%{"entries" => [], "status" => "partial"},
             [%{"code" => "alternative_support_unavailable"}]}
        end

      alternatives = Map.new(alternative["entries"], &{&1["input_id"], &1})

      rows =
        Enum.zip(pairs, result["entries"])
        |> Enum.map(fn {{a, b}, r} ->
          %{
            "id" => r["input_id"],
            "from" => a["id"],
            "to" => b["id"],
            "source_scene_id" => a["scene_id"],
            "target_scene_id" => b["scene_id"],
            "evidence_ids" => Enum.uniq(a["evidence_ids"] ++ b["evidence_ids"]),
            "answers" => r["answers"],
            "status" => r["status"],
            "alternative_support" =>
              get_in(alternatives, [r["input_id"], "answers", "other_support"])
          }
        end)

      {:ok,
       Report.new(model, "dependencies", params, %{
         status:
           if(
             extracted.status == "complete" and result["status"] == "complete" and
               alternative["status"] == "complete",
             do: "complete",
             else: "partial"
           ),
         data: %{"edges" => rows, "records" => records},
         graph: %{"nodes" => records, "edges" => rows},
         evidence: Projection.evidence(units),
         coverage: %{
           "candidate_pairs" => length(pairs),
           "tested_pairs" => result["scheduled"],
           "selection" => params["selection"]
         },
         errors: errors ++ extracted.errors,
         provenance: %{
           "extraction" => extracted.provenance,
           "evaluation" => result,
           "alternative_support" => alternative
         }
       })}
    end
  end

  defp alternative_support(params, clients, opts, pairs, units, order, registry) do
    if Map.get(params, "include_alternative_support", true) do
      removed_inputs =
        Enum.with_index(pairs, fn pair, n ->
          removed_input(pair, n, units, order, registry)
        end)

      Jev.evaluate(
        clients[:system_one],
        removed_inputs,
        [
          other_support:
            SystemOneSDK.noul(
              "Does the remaining prior material establish sufficient independent support for the use? The removed setup is unavailable."
            )
        ],
        Keyword.put_new(opts, :profile_id, "dependencies")
      )
    else
      {:ok, %{"entries" => [], "status" => "complete", "scheduled" => 0}}
    end
  end

  defp removed_input({a, b}, n, units, order, registry) do
    removed = MapSet.new(a["evidence_ids"])

    prior =
      Enum.filter(units, fn u ->
        (order[u["scene_id"]] < order[b["scene_id"]] or
           (u["scene_id"] == b["scene_id"] and
              u["ordinal"] < earliest_ordinal(b, registry))) and
          not MapSet.member?(removed, u["evidence_id"])
      end)

    %{
      "id" => "edge_#{n}",
      "state" => %{
        "remaining_prior_material" => Projection.compact(prior),
        "use" => quoted(b, registry)
      }
    }
  end

  @doc "Returns evidence-ordered setup/use candidates, including events in one scene."
  def ordered_pairs(model, records, units, targets) do
    registry = Map.new(units, &{&1["evidence_id"], &1})
    order = Map.new(Enum.with_index(model.ir.scenes), fn {scene, n} -> {scene.id, n} end)

    uses = Enum.filter(records, &matches_targets?(&1, targets, registry))

    for setup <- records,
        use <- uses,
        setup["id"] != use["id"],
        earlier?(setup, use, order, registry),
        do: {setup, use}
  end

  defp matches_targets?(_record, [], _registry), do: true

  defp matches_targets?(record, targets, registry) do
    Enum.any?(targets, &matches_target?(record, &1, registry))
  end

  defp matches_target?(record, id, _registry) when is_binary(id), do: id == record["id"]

  defp matches_target?(record, %{"id" => id}, registry) do
    id == record["scene_id"] or
      Enum.any?(record["evidence_ids"], fn evidence_id ->
        unit = registry[evidence_id]
        unit && unit["target"]["id"] == id
      end)
  end

  defp matches_target?(_, _, _), do: false

  defp earlier?(setup, use, order, registry) do
    first = order[setup["scene_id"]]
    second = order[use["scene_id"]]

    is_integer(first) and is_integer(second) and
      (first < second or
         (first == second and latest_ordinal(setup, registry) < earliest_ordinal(use, registry)))
  end

  defp earliest_ordinal(record, registry),
    do: record["evidence_ids"] |> Enum.map(&registry[&1]["ordinal"]) |> Enum.min()

  defp latest_ordinal(record, registry),
    do: record["evidence_ids"] |> Enum.map(&registry[&1]["ordinal"]) |> Enum.max()

  def affected(edges, starting_ids, limit \\ 500),
    do: walk(edges, starting_ids, %{}, limit) |> Map.keys() |> Enum.sort()

  defp walk(_, [], seen, _), do: seen

  defp walk(edges, [id | rest], seen, limit) do
    cond do
      map_size(seen) >= limit ->
        seen

      Map.has_key?(seen, id) ->
        walk(edges, rest, seen, limit)

      true ->
        walk(
          edges,
          rest ++ for(e <- edges, e["from"] == id, do: e["to"]),
          Map.put(seen, id, true),
          limit
        )
    end
  end

  defp quoted(record, registry),
    do: %{
      "claim" => record["claim"],
      "source" => Enum.map(record["evidence_ids"], &registry[&1]["text"])
    }
end
