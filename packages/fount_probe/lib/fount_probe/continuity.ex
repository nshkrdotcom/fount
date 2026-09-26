defmodule FountProbe.Continuity do
  @moduledoc "Evidence-linked state transitions with explicit chronology uncertainty."
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
             ~w(props relationships timeline commitments),
             "Extract ownership, location, physical state, explicit time, promises and relationships; keep missing transitions uncertain."
           ),
         {:ok, units} <- Projection.select(model, params["selection"]) do
      run_selected(model, params, clients, opts, extracted, units)
    end
  end

  defp run_selected(model, params, clients, opts, extracted, units) do
    prepared = prepare_pairs(model, params, extracted, units)

    %{
      records: records,
      known: known,
      pairs: pairs,
      changed_coverage: changed_coverage,
      inputs: inputs
    } = prepared

    q =
      SystemOneSDK.choice(
        "How do these exact state observations relate? An unshown transfer or elapsed time may explain a change; heading differences alone are not contradictions.",
        contradiction: "Explicit states contradict",
        explained: "An explicit explanation supports the transition",
        unknown: "A transition or chronology is unestablished"
      )

    with {:ok, result} <-
           Jev.evaluate(
             clients[:system_one],
             inputs,
             [transition: q],
             Keyword.put_new(opts, :profile_id, "continuity")
           ) do
      rows =
        Enum.zip(pairs, result["entries"])
        |> Enum.map(fn {{subject, a, b}, r} ->
          %{
            "subject" => subject,
            "from" => a,
            "to" => b,
            "evidence_ids" => Enum.uniq(a["evidence_ids"] ++ b["evidence_ids"]),
            "assessment" => r["answers"]["transition"],
            "status" => r["status"],
            "repair_scene_id" => b["scene_id"]
          }
        end)

      {:ok,
       Report.new(model, "continuity", params, %{
         status:
           if(
             result["status"] == "complete" and extracted.status == "complete" and
               changed_coverage["unmatched_changed_targets"] == [],
             do: "complete",
             else: "partial"
           ),
         data: %{
           "transitions" => rows,
           "chronology" => if(known, do: "writer_declared", else: "uncertain_reading_order"),
           "unresolved_subject_records" => Enum.filter(records, &(&1["subjects"] == []))
         },
         evidence: Projection.evidence(units),
         coverage: Map.merge(%{"transition_count" => length(pairs)}, changed_coverage),
         provenance: %{"extraction" => extracted.provenance, "evaluation" => result},
         errors:
           extracted.errors ++
             if(changed_coverage["unmatched_changed_targets"] == [],
               do: [],
               else: [%{"code" => "changed_targets_without_records"}]
             )
       })}
    end
  end

  defp prepare_pairs(model, params, extracted, units) do
    evidence = Map.new(units, &{&1["evidence_id"], &1})
    order = Map.new(Enum.with_index(model.ir.scenes), fn {s, n} -> {s.id, n} end)

    chronology =
      model.authored_items
      |> Map.values()
      |> Enum.filter(&(&1["kind"] == "story_time" and &1["status"] == "active"))
      |> Map.new(&{&1["target"]["id"], &1["value"]["order"]})

    records =
      extracted.data["records"]
      |> Enum.filter(fn r ->
        Map.get(params, "subjects", []) == [] or
          Enum.any?(r["subjects"], &(&1 in params["subjects"]))
      end)

    known = records != [] and Enum.all?(records, &is_number(chronology[&1["scene_id"]]))
    rank = fn r -> if known, do: chronology[r["scene_id"]], else: order[r["scene_id"]] end

    by_subject =
      Enum.reduce(records, %{}, fn r, acc ->
        Enum.reduce(r["subjects"], acc, fn subject, acc ->
          Map.update(acc, subject, [r], &(&1 ++ [r]))
        end)
      end)

    all_pairs =
      Enum.flat_map(Enum.sort(by_subject), fn {subject, rs} ->
        rs
        |> Enum.sort_by(rank)
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [a, b] -> {subject, a, b} end)
      end)

    {pairs, changed_coverage} =
      affected_pairs(model, all_pairs, records, units, Map.get(params, "changed_targets", []))

    inputs =
      Enum.with_index(pairs, fn {subject, a, b}, n ->
        %{
          "id" => "transition_#{n}",
          "state" => %{
            "subject" => subject,
            "earlier" => excerpts(a, evidence),
            "later" => excerpts(b, evidence),
            "chronology" =>
              if(known, do: "writer_declared_story_order", else: "reading_order_only")
          }
        }
      end)

    %{
      records: records,
      known: known,
      pairs: pairs,
      changed_coverage: changed_coverage,
      inputs: inputs
    }
  end

  @doc "Keeps transitions at and after a changed observation for each affected subject."
  def affected_pairs(_, pairs, _, _, []),
    do: {pairs, %{"changed_target_hits" => [], "unmatched_changed_targets" => []}}

  def affected_pairs(model, pairs, records, units, targets) do
    registry = Map.new(units, &{&1["evidence_id"], &1})
    scene_order = Map.new(Enum.with_index(model.ir.scenes), fn {scene, n} -> {scene.id, n} end)

    hits = Enum.map(targets, &{&1, selected_records(&1, records, registry)})
    earliest = earliest_positions(hits, registry, scene_order)

    filtered =
      Enum.filter(pairs, fn {subject, _, later} ->
        case earliest[subject] do
          nil -> false
          position -> record_position(later, registry, scene_order) >= position
        end
      end)

    coverage = %{
      "changed_target_hits" =>
        Enum.map(hits, fn {target, matching} ->
          %{"target" => target, "record_ids" => Enum.map(matching, & &1["id"])}
        end),
      "unmatched_changed_targets" => for({target, []} <- hits, do: target)
    }

    {filtered, coverage}
  end

  defp selected_records(%{"kind" => "character", "id" => id}, records, _registry),
    do: Enum.filter(records, &(id in (&1["subjects"] || [])))

  defp selected_records(%{"kind" => "scene", "id" => id}, records, _registry),
    do: Enum.filter(records, &(&1["scene_id"] == id))

  defp selected_records(%{"kind" => "element", "id" => id}, records, registry) do
    Enum.filter(records, fn record ->
      Enum.any?(
        record["evidence_ids"] || [],
        &(get_in(registry, [&1, "target", "id"]) == id)
      )
    end)
  end

  defp selected_records(_, _, _), do: []

  defp earliest_positions(hits, registry, scene_order) do
    hits
    |> Enum.flat_map(fn {_, matching} -> matching end)
    |> Enum.reduce(%{}, fn record, acc ->
      position = record_position(record, registry, scene_order)

      Enum.reduce(record["subjects"] || [], acc, fn subject, acc ->
        Map.update(acc, subject, position, &min(&1, position))
      end)
    end)
  end

  defp record_position(record, registry, scene_order) do
    ordinal =
      record["evidence_ids"]
      |> Enum.map(&(registry[&1] && registry[&1]["ordinal"]))
      |> Enum.filter(&is_integer/1)
      |> case do
        [] -> -1
        values -> Enum.min(values)
      end

    {Map.get(scene_order, record["scene_id"], -1), ordinal}
  end

  defp excerpts(r, registry),
    do: %{"claim" => r["claim"], "material" => Enum.map(r["evidence_ids"], &registry[&1]["text"])}
end
