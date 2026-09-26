defmodule FountProbe.SavedRecords do
  @moduledoc "Loads exact, complete extraction records from persisted reports when requested."
  alias FountProbe.Extraction
  alias FountProbe.Projection
  alias FountProbe.Report

  def resolve(model, params, clients, opts, kinds, question \\ nil) do
    case Map.get(params, "record_report_ids", []) do
      [] ->
        Extraction.run(
          model,
          %{"selection" => params["selection"], "kinds" => kinds, "question" => question},
          clients,
          opts
        )

      ids when is_list(ids) ->
        reuse(model, params, opts, kinds, ids)

      _ ->
        {:error, :invalid_record_report_ids}
    end
  end

  defp reuse(model, params, opts, kinds, ids) do
    reader = Keyword.get(opts, :report_reader)

    with true <- is_function(reader, 1) and ids != [] and Enum.all?(ids, &is_binary/1),
         true <- length(ids) == length(Enum.uniq(ids)),
         {:ok, units} <- Projection.select(model, params["selection"]),
         {:ok, payloads} <- read_all(ids, reader),
         :ok <- validate_all(model, payloads, units, kinds) do
      records = Enum.flat_map(payloads, &get_in(&1, ["data", "records"]))

      {:ok,
       Report.new(model, "extract_story", params, %{
         data: %{"records" => records},
         evidence: Projection.evidence(units),
         coverage: %{
           "inspected_scene_ids" => units |> Enum.map(& &1["scene_id"]) |> Enum.uniq(),
           "pending_scene_ids" => [],
           "reused_report_ids" => ids
         },
         provenance: %{"reused_report_ids" => ids}
       })}
    else
      false -> {:error, :incompatible_saved_extraction}
      {:error, :missing_report_reader} -> {:error, :missing_report_reader}
      {:error, _} -> {:error, :incompatible_saved_extraction}
    end
  end

  defp read_all(ids, reader) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, reports} ->
      read_one(reader.(id), id, reports)
    end)
  end

  defp read_one({:ok, %{"payload" => %{} = payload} = row}, id, reports) do
    if valid_row?(id, row, payload),
      do: {:cont, {:ok, reports ++ [payload]}},
      else: {:halt, {:error, :invalid_report_row}}
  end

  defp read_one({:ok, %Report{} = report}, id, reports) when report.id == id,
    do: {:cont, {:ok, reports ++ [Report.to_map(report)]}}

  defp read_one(_, _, _), do: {:halt, {:error, :report_not_found}}

  defp valid_row?(id, row, payload) do
    payload["id"] == id and row["id"] in [nil, id] and
      row["primary_revision_id"] in [nil, payload["primary_revision_id"]]
  end

  defp validate_all(model, payloads, units, kinds) do
    scenes = MapSet.new(Enum.map(units, & &1["scene_id"]))
    evidence = Map.new(Projection.evidence(units), &{&1["evidence_id"], &1})
    unit_registry = Map.new(units, &{&1["evidence_id"], &1})

    valid = Enum.all?(payloads, &valid_report?(&1, model, kinds, evidence, scenes, unit_registry))

    covered =
      Enum.reduce(payloads, MapSet.new(), fn report, acc ->
        Enum.reduce(
          get_in(report, ["coverage", "inspected_scene_ids"]) || [],
          acc,
          &MapSet.put(&2, &1)
        )
      end)

    records = Enum.flat_map(payloads, &(get_in(&1, ["data", "records"]) || []))
    ids = Enum.map(records, & &1["id"])

    if valid and MapSet.subset?(scenes, covered) and length(ids) == length(Enum.uniq(ids)),
      do: :ok,
      else: {:error, :incompatible_saved_extraction}
  end

  defp valid_report?(report, model, kinds, evidence, scenes, units) do
    records = get_in(report, ["data", "records"])
    inspected = get_in(report, ["coverage", "inspected_scene_ids"])
    supplied = report["evidence"]
    source_kinds = get_in(report, ["request", "kinds"])

    valid_report_identity?(report, model) and
      is_list(inspected) and is_list(records) and is_list(supplied) and
      is_list(source_kinds) and Enum.all?(kinds, &(&1 in source_kinds)) and
      Enum.all?(supplied, fn item -> evidence[item["evidence_id"]] == item end) and
      Enum.all?(records, &valid_record?(&1, kinds, scenes, units, supplied))
  end

  defp valid_report_identity?(report, model) do
    report["tool"] == "extract_story" and report["status"] == "complete" and
      report["screenplay_id"] == model.id and
      report["primary_revision_id"] == model.revision.id and
      is_list(report["source_revision_ids"]) and
      model.revision.id in report["source_revision_ids"]
  end

  defp valid_record?(r, kinds, scenes, units, supplied) when is_map(r) do
    supplied_ids = MapSet.new(supplied, & &1["evidence_id"])

    valid_record_identity?(r, kinds, scenes) and
      is_list(r["evidence_ids"]) and r["evidence_ids"] != [] and
      Enum.all?(r["evidence_ids"], &valid_record_evidence?(&1, r, units, supplied_ids))
  end

  defp valid_record?(_, _, _, _, _), do: false

  defp valid_record_identity?(r, kinds, scenes),
    do: is_binary(r["id"]) and r["kind"] in kinds and MapSet.member?(scenes, r["scene_id"])

  defp valid_record_evidence?(id, record, units, supplied_ids) do
    case units[id] do
      %{"revision_id" => revision_id, "scene_id" => scene_id} ->
        revision_id == record["revision_id"] and scene_id == record["scene_id"] and
          MapSet.member?(supplied_ids, id)

      _ ->
        false
    end
  end
end
