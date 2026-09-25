defmodule FountProbe.Retrieval do
  @moduledoc "Revision-explicit lexical and semantic retrieval with honest inspected coverage."
  alias FountProbe.{Projection, Jev, Report}

  def run(model, params, clients, opts \\ []) do
    revisions = Map.get(params, "revision_ids", [model.revision.id])
    selection = Map.get(params, "selection", %{"whole_screenplay" => true})
    filters = Map.get(params, "filters", %{})

    results =
      Enum.map(revisions, fn id ->
        fetched = if id == model.revision.id, do: {:ok, model}, else: history(model.id, id, opts)

        case fetched do
          {:ok, source} when source.id == model.id ->
            with {:ok, units} <- Projection.select(source, selection, inclusion(filters)) do
              eligible = Enum.filter(units, &filter?(&1, source, filters))
              query = params["query"]
              tokens = Regex.scan(~r/[\p{L}\p{N}]+/u, String.downcase(query)) |> List.flatten()

              candidate =
                if params["mode"] == "inspect_all" and params["exact_phrase"] != true,
                  do: eligible,
                  else:
                    Enum.filter(
                      eligible,
                      &matches?(&1["text"], query, tokens, params["exact_phrase"] == true)
                    )

              semantic = not is_nil(clients[:system_one]) and params["exact_phrase"] != true

              if semantic do
                inputs =
                  Enum.map(
                    candidate,
                    &%{
                      "id" => &1["evidence_id"],
                      "state" => %{"query" => query, "passage" => &1["text"]}
                    }
                  )

                question =
                  SystemOneSDK.noul(
                    "Is this passage substantively relevant to the original writer query, rather than merely sharing a word?"
                  )

                case Jev.evaluate(
                       clients.system_one,
                       inputs,
                       [relevant: question],
                       Keyword.put_new(opts, :profile_id, "retrieval")
                     ) do
                  {:ok, result} ->
                    by_id = Map.new(result["entries"], &{&1["input_id"], &1})

                    hits =
                      candidate
                      |> Enum.map(fn u ->
                        a = get_in(by_id, [u["evidence_id"], "answers", "relevant"])
                        Map.put(u, "relevance", a)
                      end)
                      |> Enum.filter(
                        &(is_number(get_in(&1, ["relevance", "probability"])) and
                            &1["relevance"]["probability"] >= 0.5)
                      )

                    {:ok, source, hits, candidate, result}

                  error ->
                    error
                end
              else
                {:ok, source, candidate, eligible,
                 %{"status" => "complete", "mode" => "unicode_lexical", "scheduled" => 0}}
              end
            end

          {:ok, _} ->
            {:error, :foreign_history}

          error ->
            error
        end
      end)

    failures =
      Enum.zip(revisions, results)
      |> Enum.flat_map(fn {id, result} ->
        case result do
          {:error, reason} ->
            [
              %{
                "input_id" => id,
                "code" => "revision_search_failed",
                "message" => inspect(reason)
              }
            ]

          _ ->
            []
        end
      end)

    hits =
      Enum.flat_map(results, fn
        {:ok, _, h, _, _} -> h
        _ -> []
      end)

    inspected =
      Enum.flat_map(results, fn
        {:ok, _, _, units, _} -> units
        _ -> []
      end)

    traces =
      Enum.flat_map(results, fn
        {:ok, _, _, _, trace} -> [trace]
        _ -> []
      end)

    sorted =
      Enum.sort_by(
        hits,
        &{-(get_in(&1, ["relevance", "probability"]) || 0), &1["revision_id"], &1["ordinal"]}
      )

    limit = Map.get(params, "limit", 20)

    status =
      if failures == [] and Enum.all?(traces, &(&1["status"] == "complete")),
        do: "complete",
        else: "partial"

    sources =
      Enum.flat_map(results, fn
        {:ok, m, _, _, _} -> [m.revision.id]
        _ -> []
      end)

    {:ok,
     Report.new(model, "search", params, %{
       status: status,
       source_revision_ids: Enum.uniq([model.revision.id | sources]),
       data: %{
         "hits" => Enum.take(sorted, limit),
         "matching_count" => length(hits),
         "returned_count" => min(length(hits), limit)
       },
       evidence: Projection.evidence(inspected),
       errors: failures,
       provenance: %{"evaluations" => traces},
       coverage: %{
         "revision_ids_requested" => revisions,
         "inspected_evidence_ids" => Enum.map(inspected, & &1["evidence_id"]),
         "retrieval_mode" => Map.get(params, "mode", "retrieve"),
         "exhaustive_semantic_inspection" =>
           params["mode"] == "inspect_all" and params["exact_phrase"] != true and
             not is_nil(clients[:system_one]) and status == "complete"
       }
     })}
  end

  defp history(sid, rid, opts) do
    case Keyword.get(opts, :history_reader) do
      f when is_function(f, 2) -> f.(sid, rid)
      _ -> {:error, :history_reader_required}
    end
  end

  defp inclusion(f),
    do: [
      include_notes: f["include_notes"] == true,
      include_boneyards: f["include_boneyards"] == true,
      include_omitted: f["include_omitted"] == true
    ]

  defp matches?(text, query, _tokens, true),
    do: Regex.match?(Regex.compile!(Regex.escape(query), "iu"), text)

  defp matches?(text, _, tokens, false),
    do: Enum.any?(tokens, &String.contains?(String.downcase(text), &1))

  defp filter?(u, model, f) do
    scene = Fount.Query.scene_for(model, u["target"]["id"])
    types = f["element_types"]
    location = f["location"]
    cast_ids = f["character_ids"] || []
    role = Map.get(f, "character_role", "speaker")

    cast_ok =
      cast_ids == [] or
        Enum.any?(cast_ids, fn id ->
          case role do
            "speaker" ->
              Enum.any?(
                Fount.Query.character_dialogue(model, id),
                &(u["target"]["id"] in [&1.cue_id | &1.body_ids])
              )

            "reference" ->
              Enum.any?(
                Fount.Query.character_mentions(model, id),
                &(&1.element_id == u["target"]["id"] and &1.role != :speaker_cue)
              )

            "declared_present" ->
              Enum.any?(
                Map.values(model.authored_items),
                &(&1["kind"] == "perspective_access" and &1["value"]["character_id"] == id and
                    &1["target"]["id"] == u["scene_id"])
              )
          end
        end)

    collections = f["authored_collection_ids"] || []

    collection_ok =
      collections == [] or
        Enum.any?(collections, fn id ->
          item = model.authored_items[id]

          item &&
            (u["scene_id"] in (item["value"]["scene_ids"] || []) or
               u["target"]["id"] in (item["value"]["element_ids"] || []))
        end)

    (is_nil(f["scene_ids"]) or u["scene_id"] in f["scene_ids"]) and
      (is_nil(types) or u["type"] in types) and
      (is_nil(location) or
         (scene &&
            String.contains?(
              String.downcase(Fount.Query.node(model, scene.heading_id).text),
              String.downcase(location)
            ))) and cast_ok and collection_ok
  end
end
