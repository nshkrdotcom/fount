defmodule FountWorkshop.PhaseNineIntelligenceTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.Acquisition.CapabilityMeasurements
  alias Fount.Observe.Sandbox
  alias Fount.Screenplay
  alias FountWorkshop.Request
  alias FountWorkshop.Session
  alias FountWorkshop.Writing.{Context, Intelligence}

  test "provider-free preflight exposes analysis and generation caps without changing canon" do
    model = screenplay()
    request = request(model, "alternatives")

    assert {:ok, preflight} = Session.preflight(model, request, max_inference_calls: 9)
    assert preflight["changes_canon"] == false
    assert preflight["generation"]["configured_max_inference_calls"] == 9
    assert preflight["analysis"]["status"] == "available"
    assert preflight["analysis"]["playbook"] == "scene_doctor"
    assert model.revision.id == request["base_revision_id"]
  end

  test "prewrite intelligence produces a writer packet and keeps diagnosis separate from pages" do
    model = screenplay()
    request = request(model, "alternatives")
    {:ok, context} = Context.build(model, request)
    [scene] = model.ir.scenes
    spec = CapabilityMeasurements.scene_engine()

    provider =
      Sandbox.new!(%{
        "capability:scene_engine:scene:#{scene.id}" => answers(spec["questions"])
      })

    assert {:ok, enriched} =
             Intelligence.enrich_preparation(model, request, context, %{observe: provider})

    packet = enriched.data["writer_intelligence"]
    assert packet["playbook"] == "scene_doctor"
    assert packet["candidate"] == nil
    assert packet["status"] in ["complete", "partial"]
    assert is_list(packet["diagnoses"])
    assert is_map(packet["resource_usage"])
  end

  test "notes keep reaction, proposed cause and proposed treatment as separate fields" do
    model = screenplay()
    [scene] = model.ir.scenes

    request =
      request(model, "notes")
      |> put_in(["selection"], %{"targets" => [%{"kind" => "scene", "id" => scene.id}]})
      |> put_in(["options"], %{
        "note_ids" => [],
        "external_notes" => [
          %{
            "reaction" => "The midpoint feels repetitive.",
            "suggested_cause" => "The scenes may repeat the same tactic.",
            "suggested_treatment" => "Force a different choice in the second scene."
          }
        ]
      })

    assert {:ok, validated} = Request.validate(model, request)
    {:ok, context} = Context.build(model, validated)

    assert {:ok, enriched} = Intelligence.enrich_preparation(model, validated, context, %{})
    [note] = enriched.data["note_triage"]
    assert note["reaction"] == "The midpoint feels repetitive."
    assert note["suggested_cause"] == "The scenes may repeat the same tactic."
    assert note["suggested_treatment"] == "Force a different choice in the second scene."
    assert enriched.data["writer_intelligence"]["status"] == "not_run"
  end

  test "protected strengths and intended effect are additive validated workflow options" do
    model = screenplay()

    request =
      request(model, "alternatives")
      |> put_in(["options"], %{
        "protected_strengths" => ["Mara's refusal remains quiet rather than triumphant."],
        "intended_effect" => "Increase pressure without making Mara more verbally explicit."
      })

    assert {:ok, validated} = Request.validate(model, request)

    assert get_in(validated, ["options", "protected_strengths"]) ==
             ["Mara's refusal remains quiet rather than triumphant."]
  end

  test "revision intelligence checks are advisory and cannot accept or reject a candidate" do
    packet = %{
      "status" => "complete",
      "revision_comparison" => %{
        "protected_strengths" => %{
          "declared" => ["Keep the private history"],
          "status" => "evidence_of_preservation"
        },
        "collateral_change" => %{"risk_support" => %{"voice_drift" => 1}}
      }
    }

    checks = Intelligence.revision_checks(packet)
    assert Enum.all?(checks, &(&1["severity"] == "advisory"))
    assert Enum.any?(checks, &(&1["status"] == "review"))
  end

  defp screenplay do
    Screenplay.new(
      scenes: [
        %{
          heading: "INT. SERVICE OFFICE - NIGHT",
          elements: [
            %{type: :action, text: "Mara keeps one hand on the sealed ledger."},
            %{type: :character, text: "DAN"},
            %{type: :dialogue, text: "You can still leave it."},
            %{type: :character, text: "MARA"},
            %{type: :dialogue, text: "I know."}
          ]
        }
      ]
    )
  end

  defp request(model, workflow) do
    [scene] = model.ir.scenes

    %{
      "version" => 1,
      "workflow" => workflow,
      "mode" => "revise",
      "base_revision_id" => model.revision.id,
      "instruction" => "Make the choice cost Mara something visible without explaining it away.",
      "selection" => %{"targets" => [%{"kind" => "scene", "id" => scene.id}]},
      "constraints" => [],
      "alternatives" => 2,
      "options" =>
        if(workflow == "notes", do: %{"note_ids" => [], "external_notes" => []}, else: %{})
    }
  end

  defp answers(questions) do
    Map.new(questions, fn {key, question} ->
      value =
        case question.kind do
          :noul -> 0.9
          :choice -> choice(question)
          :score -> 0
        end

      {to_string(key), value}
    end)
  end

  defp choice(question) do
    labels = Enum.map(question.criteria, &elem(&1, 0))
    selected = hd(labels)
    remainder = if length(labels) > 1, do: 0.1 / (length(labels) - 1), else: 0.0

    %{
      "probabilities" => Map.new(labels, &{&1, if(&1 == selected, do: 0.9, else: remainder)}),
      "choice" => selected,
      "confidence" => 0.9
    }
  end
end
