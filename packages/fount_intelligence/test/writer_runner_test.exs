defmodule Fount.Intelligence.WriterRunnerTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.Acquisition.Planner
  alias Fount.Intelligence.Playbooks.WriterRunner
  alias Fount.Intelligence.Reporting.WriterPacket
  alias Fount.Observe.Sandbox

  defp model do
    Fount.Screenplay.new(
      scenes: [
        %{
          heading: "INT. INTERROGATION ROOM - NIGHT",
          elements: [
            %{type: :action, text: "Mara closes the file and waits."},
            %{type: :character, text: "DAN"},
            %{type: :dialogue, text: "You already know what I came to say."},
            %{type: :character, text: "MARA"},
            %{type: :dialogue, text: "Then say something I don't know."}
          ]
        }
      ]
    )
  end

  defp request do
    %{
      "concern" => %{
        "statement" => "The interrogation loses pressure after the first exchange.",
        "desired_effect" => "sustained entrapment without making Mara overtly aggressive",
        "protected_strengths" => ["Mara remains restrained"]
      },
      "hypotheses" => [
        %{
          "id" => "h-tactic",
          "code" => "repeated_tactic",
          "hypothesis" => "The exchange stops changing tactic or leverage.",
          "alternatives" => ["The stasis may be intentional entrapment."],
          "context" => %{}
        },
        %{
          "id" => "h-info",
          "code" => "information_without_consequence",
          "hypothesis" => "New information arrives without creating a consequence.",
          "context" => %{}
        }
      ]
    }
  end

  defp provider(model, request) do
    {:ok, plan} = Planner.plan(model, request)

    base =
      Map.new(plan["base_inputs"], fn input ->
        {input["id"], %{"relevant" => 0.9}}
      end)

    contextual =
      Map.new(plan["hypotheses"], fn hypothesis ->
        {"hypothesis:" <> hypothesis["id"], %{"support" => 0.9, "counterevidence" => 0.1}}
      end)

    Sandbox.new!(Map.merge(base, contextual))
  end

  test "Sandbox drives the multi-pass writer playbook deterministically" do
    model = model()
    request = request()
    clients = %{observe: provider(model, request)}

    assert {:ok, %WriterPacket{} = first} =
             WriterRunner.run(model, "scene_doctor", request, clients, run_id: "phase-five-test")

    assert {:ok, %WriterPacket{} = second} =
             WriterRunner.run(model, "scene_doctor", request, clients, run_id: "phase-five-test")

    assert WriterPacket.to_map(first) == WriterPacket.to_map(second)
    assert first.status == "complete"
    assert length(first.diagnoses) == 2
    assert first.trajectory == []
    assert Enum.map(first.provenance["analysis_passes"], & &1["kind"]) == [
             "observe_base",
             "pure_evidence_need_reduction",
             "contextual_observe",
             "pure_diagnosis"
           ]
  end

  test "preflight validates context and reports resource caps without spending a provider call" do
    model = model()

    assert {:ok, preflight} =
             WriterRunner.preflight(model, "scene_doctor", request(),
               max_playbook_provider_requests: 3,
               max_measurement_states: 4
             )

    assert preflight["caps"]["max_provider_requests"] == 3
    assert preflight["estimate"]["provider_requests_before_retries_estimate"] <= 3
    assert preflight["estimate"]["hosted_cost"] == nil
  end

  test "partial budget cannot be reported as complete coverage" do
    model = model()
    request = request()
    clients = %{observe: provider(model, request)}

    assert {:ok, packet} =
             WriterRunner.run(model, "scene_doctor", request, clients,
               max_playbook_provider_requests: 1,
               max_measurement_states: 1
             )

    assert packet.status == "partial"
    assert packet.coverage["skipped_or_failed_request_ids"] != []
    assert packet.missing_evidence != []
    refute packet.coverage["status"] == "complete"
  end

  test "unknown contextual slot fails in preflight before run" do
    model = model()

    request =
      put_in(
        request(),
        ["hypotheses", Access.at(0), "context"],
        %{"not_declared_by_lens" => true}
      )

    assert {:error, _} = WriterRunner.preflight(model, "scene_doctor", request)
  end

  test "source-selection truncation remains partial even when acquired work succeeds" do
    model = model()
    request = request()

    {:ok, plan} = Planner.plan(model, request, max_evidence_fragments: 1)
    assert plan["evidence_scope"]["truncated_by_host_limit"]

    base = Map.new(plan["base_inputs"], fn input -> {input["id"], %{"relevant" => 0.9}} end)

    contextual =
      Map.new(plan["hypotheses"], fn hypothesis ->
        {"hypothesis:" <> hypothesis["id"], %{"support" => 0.9, "counterevidence" => 0.1}}
      end)

    clients = %{observe: Sandbox.new!(Map.merge(base, contextual))}

    assert {:ok, packet} =
             WriterRunner.run(model, "scene_doctor", request, clients,
               max_evidence_fragments: 1,
               run_id: "phase-five-selection-cap"
             )

    assert packet.status == "partial"
    assert packet.coverage["evidence_scope"]["truncated_by_host_limit"]
  end

  test "hypotheses cannot cite source evidence outside the selected set" do
    model = model()
    bad = put_in(request(), ["hypotheses", Access.at(0), "evidence_ids"], ["missing-evidence-id"])
    assert {:error, :invalid_hypotheses} = Planner.plan(model, bad)
  end
end
