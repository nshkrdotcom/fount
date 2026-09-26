defmodule FountProbe.Retrieval do
  @moduledoc "Revision-explicit lexical and semantic retrieval with honest inspected coverage."
  alias FountProbe.Jev
  alias FountProbe.Projection
  alias FountProbe.Report

  def run(model, params, clients, opts \\ []) do
    revisions = Map.get(params, "revision_ids", [model.revision.id])
    selection = Map.get(params, "selection", %{"whole_screenplay" => true})
    filters = Map.get(params, "filters", %{})

    results =
      Enum.map(revisions, &search_revision(model, &1, selection, filters, params, clients, opts))

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

  defp search_revision(model, id, selection, filters, params, clients, opts) do
    fetched = if id == model.revision.id, do: {:ok, model}, else: history(model.id, id, opts)

    case fetched do
      {:ok, source} when source.id == model.id ->
        with {:ok, units} <- Projection.select(source, selection, inclusion(filters)) do
          eligible = Enum.filter(units, &filter?(&1, source, filters))
          query = params["query"]
          tokens = Regex.scan(~r/[\p{L}\p{N}]+/u, String.downcase(query)) |> List.flatten()

          candidate = candidates(eligible, query, tokens, params)

          search_candidates(source, eligible, candidate, query, params, clients, opts)
        end

      {:ok, _} ->
        {:error, :foreign_history}

      error ->
        error
    end
  end

  defp candidates(eligible, query, tokens, params) do
    if params["mode"] == "inspect_all" and params["exact_phrase"] != true,
      do: eligible,
      else:
        Enum.filter(
          eligible,
          &matches?(&1["text"], query, tokens, params["exact_phrase"] == true)
        )
  end

  defp search_candidates(source, eligible, candidate, query, params, clients, opts) do
    if not is_nil(clients[:system_one]) and params["exact_phrase"] != true do
      semantic_search(source, candidate, query, clients, opts)
    else
      {:ok, source, candidate, eligible,
       %{"status" => "complete", "mode" => "unicode_lexical", "scheduled" => 0}}
    end
  end

  defp semantic_search(source, candidate, query, clients, opts) do
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
            Map.put(u, "relevance", get_in(by_id, [u["evidence_id"], "answers", "relevant"]))
          end)
          |> Enum.filter(&relevant?/1)

        {:ok, source, hits, candidate, result}

      error ->
        error
    end
  end

  defp relevant?(unit),
    do:
      is_number(get_in(unit, ["relevance", "probability"])) and
        unit["relevance"]["probability"] >= 0.5

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

  defp filter?(unit, model, filters) do
    matching_scene?(unit, filters) and matching_type?(unit, filters) and
      matching_location?(unit, model, filters) and matching_cast?(unit, model, filters) and
      matching_collection?(unit, model, filters)
  end

  defp matching_scene?(u, f), do: is_nil(f["scene_ids"]) or u["scene_id"] in f["scene_ids"]
  defp matching_type?(u, f), do: is_nil(f["element_types"]) or u["type"] in f["element_types"]

  defp matching_location?(u, model, f) do
    location = f["location"]
    scene = Fount.Query.scene_for(model, u["target"]["id"])

    is_nil(location) or
      (scene &&
         String.contains?(
           String.downcase(Fount.Query.node(model, scene.heading_id).text),
           String.downcase(location)
         ))
  end

  defp matching_cast?(u, model, f) do
    ids = f["character_ids"] || []
    role = Map.get(f, "character_role", "speaker")
    ids == [] or Enum.any?(ids, &cast_match?(u, model, role, &1))
  end

  defp cast_match?(u, model, "speaker", id) do
    Enum.any?(
      Fount.Query.character_dialogue(model, id),
      &(u["target"]["id"] in [&1.cue_id | &1.body_ids])
    )
  end

  defp cast_match?(u, model, "reference", id) do
    Enum.any?(
      Fount.Query.character_mentions(model, id),
      &(&1.element_id == u["target"]["id"] and &1.role != :speaker_cue)
    )
  end

  defp cast_match?(u, model, "declared_present", id) do
    Enum.any?(
      Map.values(model.authored_items),
      &(&1["kind"] == "perspective_access" and &1["value"]["character_id"] == id and
          &1["target"]["id"] == u["scene_id"])
    )
  end

  defp matching_collection?(u, model, f) do
    ids = f["authored_collection_ids"] || []

    ids == [] or
      Enum.any?(ids, fn id ->
        item = model.authored_items[id]

        item &&
          (u["scene_id"] in (item["value"]["scene_ids"] || []) or
             u["target"]["id"] in (item["value"]["element_ids"] || []))
      end)
  end
end
