defmodule FountRun.ScreenplayPipelineTest do
  use ExUnit.Case, async: true

  alias FountRun.{PipelineRequest, StageRegistry}

  defp workshop_request do
    %{
      "version" => 1,
      "workflow" => "develop",
      "mode" => "draft",
      "base_revision_id" => Fount.ID.v4(),
      "instruction" => "Open on a visible choice.",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "alternatives" => 1,
      "options" => %{"placement" => %{"kind" => "start"}}
    }
  end

  test "P01 pipeline envelope is closed and Phase 04 stages are registered" do
    assert {:ok, envelope} = PipelineRequest.new(workshop_request())
    assert envelope["kind"] == "screenplay_v1"

    assert {:error, {:unknown_field, "future"}} =
             PipelineRequest.validate(Map.put(envelope, "future", true))

    assert {:ok, registry} = StageRegistry.new()
    assert {:ok, FountRun.PipelineHandler} = StageRegistry.fetch(registry, "intake")
    assert {:ok, FountRun.PipelineHandler} = StageRegistry.fetch(registry, "investigate")
    assert {:ok, FountRun.PipelineHandler} = StageRegistry.fetch(registry, "plan")
    assert {:ok, FountRun.WorkshopHandler} = StageRegistry.fetch(registry, "write")
    assert {:ok, FountRun.PipelineHandler} = StageRegistry.fetch(registry, "check")
    assert {:ok, FountRun.PipelineHandler} = StageRegistry.fetch(registry, "iterate")
  end

  test "P02 investigation metadata survives closed envelope advancement" do
    {:ok, envelope} = PipelineRequest.new(workshop_request())
    investigation_id = Fount.ID.v4()

    assert {:ok, advanced} =
             PipelineRequest.advance(envelope, %{
               investigation_request: Map.put(workshop_request(), "workflow", "investigate"),
               investigation_session_id: investigation_id,
               report_ids: [Fount.ID.v4()],
               uncertainty: [%{"kind" => "gap", "detail" => "motive remains unstated"}]
             })

    assert advanced["investigation_session_id"] == investigation_id
    assert [%{"kind" => "gap"} = gap] = advanced["uncertainty"]
    assert gap["detail"] =~ "motive"
  end

  test "P03 public strategy submission exists while later decision kinds stay unavailable" do
    assert Code.ensure_loaded?(FountWorkshop.Session)
    assert function_exported?(FountRun, :submit_decision, 4)
    assert function_exported?(FountWorkshop.Session, :prepare_only, 4)
    assert function_exported?(FountWorkshop.Session, :plan_only, 4)

    assert {:ok, registry} = StageRegistry.new()

    assert {:error, {:stage_handler_unavailable, "decide"}} =
             StageRegistry.fetch(registry, "decide")

    assert {:error, {:stage_handler_unavailable, "deliver"}} =
             StageRegistry.fetch(registry, "deliver")
  end

  test "P04 repair lineage fields are closed and preserve the prior candidate" do
    {:ok, envelope} = PipelineRequest.new(workshop_request())
    source = Fount.ID.v4()

    assert {:ok, advanced} =
             PipelineRequest.advance(envelope, %{
               source_candidate_id: source,
               finding: "Protected beat changed",
               candidate_ids: [source],
               lineage: [%{"candidate_id" => source, "operation" => "check"}]
             })

    assert advanced["source_candidate_id"] == source
    assert advanced["finding"] == "Protected beat changed"
    assert [%{"candidate_id" => ^source}] = advanced["lineage"]
  end

  test "P05 check binding fields retain candidates, reports and fingerprints" do
    {:ok, envelope} = PipelineRequest.new(workshop_request())
    candidate = Fount.ID.v4()
    report = Fount.ID.v4()
    fingerprint = String.duplicate("a", 64)

    assert {:ok, advanced} =
             PipelineRequest.advance(envelope, %{
               candidate_ids: [candidate],
               report_ids: [report],
               check_set_fingerprint: fingerprint
             })

    assert advanced["candidate_ids"] == [candidate]
    assert advanced["report_ids"] == [report]
    assert advanced["check_set_fingerprint"] == fingerprint
  end

  test "P06 malformed resume identity is rejected instead of silently widened" do
    {:ok, envelope} = PipelineRequest.new(workshop_request())

    assert {:error, {:invalid_field, "strategy_session_id"}} =
             PipelineRequest.advance(envelope, %{strategy_session_id: "not-a-uuid"})

    assert {:error, {:invalid_field, "check_set_fingerprint"}} =
             PipelineRequest.advance(envelope, %{check_set_fingerprint: "short"})
  end

  test "P07 Phase 05 acceptance and delivery are not exposed by the Phase 04 registry" do
    assert {:ok, registry} = StageRegistry.new()
    refute Map.has_key?(registry, "decide")
    refute Map.has_key?(registry, "deliver")
    refute function_exported?(FountRun, :deliver, 4)
    refute function_exported?(FountRun, :approve_run, 4)
  end
end
