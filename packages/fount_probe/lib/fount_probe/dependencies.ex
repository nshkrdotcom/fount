defmodule FountProbe.Dependencies do
  @moduledoc "Tests proposed setup/use edges, including alternative support in an actually ablated context."
  alias FountProbe.{Extraction, Projection, Jev, Report}

  def run(model, params, clients, opts \\ []) do
    request = %{
      "selection" => params["selection"],
      "kinds" => ~w(events propositions props commitments),
      "question" => "Identify setups and later uses that may depend on them."
    }

    with {:ok, extracted} <- Extraction.run(model, request, clients, opts),
         {:ok, units} <- Projection.select(model, params["selection"]) do
      registry = Map.new(units, &{&1["evidence_id"], &1})
      records = extracted.data["records"]
      order = Map.new(Enum.with_index(model.ir.scenes), fn {s, n} -> {s.id, n} end)
      targets = params["targets"]

      uses =
        Enum.filter(records, fn r ->
          targets == [] or
            Enum.any?(targets, fn
              t when is_binary(t) ->
                t == r["id"]

              t ->
                t["id"] == r["scene_id"] or
                  Enum.any?(r["evidence_ids"], &(registry[&1]["target"]["id"] == t["id"]))
            end)
        end)

      pairs =
        for a <- records,
            b <- uses,
            a["id"] != b["id"],
            order[a["scene_id"]] < order[b["scene_id"]],
            do: {a, b}

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

      with {:ok, result} <-
             Jev.evaluate(
               clients[:system_one],
               inputs,
               questions,
               Keyword.put_new(opts, :profile_id, "dependencies")
             ) do
        alternative =
          if Map.get(params, "include_alternative_support", true) do
            removed_inputs =
              Enum.with_index(pairs, fn {a, b}, n ->
                removed = MapSet.new(a["evidence_ids"])

                prior =
                  Enum.filter(units, fn u ->
                    order[u["scene_id"]] < order[b["scene_id"]] and
                      not MapSet.member?(removed, u["evidence_id"])
                  end)

                %{
                  "id" => "edge_#{n}",
                  "state" => %{
                    "remaining_prior_material" => Projection.compact(prior),
                    "use" => quoted(b, registry)
                  }
                }
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
  end

  def affected(edges, starting_ids, limit \\ 500),
    do: walk(edges, starting_ids, MapSet.new(), limit) |> MapSet.to_list() |> Enum.sort()

  defp walk(_, [], seen, _), do: seen

  defp walk(edges, [id | rest], seen, limit) do
    cond do
      MapSet.size(seen) >= limit ->
        seen

      MapSet.member?(seen, id) ->
        walk(edges, rest, seen, limit)

      true ->
        walk(
          edges,
          rest ++ for(e <- edges, e["from"] == id, do: e["to"]),
          MapSet.put(seen, id),
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
