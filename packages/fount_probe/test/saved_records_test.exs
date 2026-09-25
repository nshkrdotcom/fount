defmodule FountProbe.SavedRecordsTest do
  use ExUnit.Case, async: true

  test "reuses complete, current-revision extraction records without an inference client" do
    {model, report, params} = fixture()

    reader = fn id ->
      if id == report.id,
        do: {:ok, %{"payload" => FountProbe.Report.to_map(report)}},
        else: {:error, :not_found}
    end

    assert {:ok, reused} =
             FountProbe.SavedRecords.resolve(model, params, %{}, [report_reader: reader], [
               "events"
             ])

    assert reused.data["records"] == report.data["records"]
    assert reused.coverage["reused_report_ids"] == [report.id]
    assert reused.status == "complete"
  end

  test "rejects a report from another revision and an incomplete report" do
    {model, report, params} = fixture()
    wrong = %{report | primary_revision_id: Fount.ID.v4()}
    reader = fn _ -> {:ok, %{"payload" => FountProbe.Report.to_map(wrong)}} end

    assert {:error, :incompatible_saved_extraction} =
             FountProbe.SavedRecords.resolve(model, params, %{}, [report_reader: reader], [
               "events"
             ])

    incomplete = %{report | status: "partial"}
    reader = fn _ -> {:ok, %{"payload" => FountProbe.Report.to_map(incomplete)}} end

    assert {:error, :incompatible_saved_extraction} =
             FountProbe.SavedRecords.resolve(model, params, %{}, [report_reader: reader], [
               "events"
             ])
  end

  test "rejects records with forged evidence and reports lacking selected scene coverage" do
    {model, report, params} = fixture()

    forged = %{
      report
      | data: %{"records" => [Map.put(hd(report.data["records"]), "evidence_ids", ["forged"])]}
    }

    reader = fn _ -> {:ok, %{"payload" => FountProbe.Report.to_map(forged)}} end

    assert {:error, :incompatible_saved_extraction} =
             FountProbe.SavedRecords.resolve(model, params, %{}, [report_reader: reader], [
               "events"
             ])

    uncovered = put_in(report.coverage["inspected_scene_ids"], [])
    reader = fn _ -> {:ok, %{"payload" => FountProbe.Report.to_map(uncovered)}} end

    assert {:error, :incompatible_saved_extraction} =
             FountProbe.SavedRecords.resolve(model, params, %{}, [report_reader: reader], [
               "events"
             ])
  end

  defp fixture do
    model =
      Fount.Screenplay.new(
        scenes: [
          %{
            heading: "INT. SHED - DAY",
            elements: [%{type: :action, text: "A key opens the box."}]
          }
        ]
      )

    selection = %{"whole_screenplay" => true}
    {:ok, units} = FountProbe.Projection.select(model, selection)
    [scene] = model.ir.scenes
    [unit] = Enum.filter(units, &(&1["type"] == "action"))

    record = %{
      "id" => "#{scene.id}:key",
      "kind" => "events",
      "claim" => "The key opens the box",
      "subjects" => [],
      "evidence_ids" => [unit["evidence_id"]],
      "uncertainty" => "",
      "scene_id" => scene.id,
      "revision_id" => model.revision.id
    }

    report =
      FountProbe.Report.new(
        model,
        "extract_story",
        %{"selection" => selection, "kinds" => ["events"]},
        %{
          data: %{"records" => [record]},
          evidence: FountProbe.Projection.evidence(units),
          coverage: %{"inspected_scene_ids" => [scene.id], "pending_scene_ids" => []}
        }
      )

    {model, report, %{"selection" => selection, "record_report_ids" => [report.id]}}
  end
end
