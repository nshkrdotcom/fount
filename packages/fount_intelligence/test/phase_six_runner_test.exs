defmodule Fount.Intelligence.PhaseSixRunnerTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence
  alias Fount.Intelligence.Acquisition.CapabilityMeasurements
  alias Fount.Intelligence.TestSupport.PhaseSixFixture
  alias Fount.Observe.Sandbox

  test "scene doctor runs one source-visible measurement per selected scene and returns writer packet" do
    screenplay = PhaseSixFixture.screenplay()
    scene = hd(screenplay.ir.scenes)

    request = %{
      "selection" => %{"targets" => [%{"kind" => "scene", "id" => scene.id}]},
      "subject" => %{"scene_id" => scene.id},
      "story_world_records" => PhaseSixFixture.records(screenplay),
      "concern" => %{"summary" => "The office scene may run past its strongest handoff."},
      "intent" => %{"desired_effect" => "urgent bargaining"},
      "protected_strengths" => ["Dan keeps quiet control of the key"]
    }

    {:ok, spec} = CapabilityMeasurements.fetch("scene_engine")
    fixture = Map.new(spec["questions"], fn {key, _question} -> {to_string(key), 0.9} end)
    provider = Sandbox.new!(%{"capability:scene_engine:scene:#{scene.id}" => fixture})

    {:ok, packet} =
      Intelligence.run_capability_playbook(
        screenplay,
        "scene_doctor",
        request,
        %{observe: provider}
      )

    assert packet.playbook == "scene_doctor"
    assert packet.candidate == nil
    assert packet.evidence != []
    assert Map.has_key?(packet.derived_state, "scene_engine")
    assert {:ok, markdown} = Intelligence.render_packet(packet, :markdown)
    assert String.contains?(markdown, "Inspect source evidence")
  end

  test "preflight dispatches no provider and reports selected source coverage" do
    screenplay = PhaseSixFixture.screenplay()
    scene = hd(screenplay.ir.scenes)

    {:ok, preflight} =
      Intelligence.preflight_capability(
        screenplay,
        "scene_engine",
        %{
          "selection" => %{"targets" => [%{"kind" => "scene", "id" => scene.id}]},
          "subject" => %{"scene_id" => scene.id},
          "story_world_records" => PhaseSixFixture.records(screenplay)
        }
      )

    assert preflight["family"] == "scene_engine"
    assert preflight["coverage"]["selected_scene_count"] == 1
    assert preflight["estimate"]["provider_requests_before_retries_estimate"] >= 0
  end

  test "selection and provider caps report partial coverage" do
    screenplay = PhaseSixFixture.screenplay()
    scenes = Enum.take(screenplay.ir.scenes, 2)
    selection = %{"targets" => Enum.map(scenes, &%{"kind" => "scene", "id" => &1.id})}
    request = %{"selection" => selection, "subject" => %{"scene_id" => hd(scenes).id}}

    {:ok, preflight} =
      Intelligence.preflight_capability(screenplay, "scene_engine", request,
        max_capability_scenes: 1,
        max_capability_fragments_per_scene: 1
      )

    assert preflight["coverage"]["scene_cap_reached"]
    assert preflight["coverage"]["fragment_cap_reached_scene_ids"] != []

    {:ok, spec} = CapabilityMeasurements.fetch("scene_engine")

    fixtures =
      Map.new(
        scenes,
        &{"capability:scene_engine:scene:#{&1.id}", sandbox_answers(spec["questions"])}
      )

    {:ok, result} =
      Intelligence.run_capability(
        screenplay,
        "scene_engine",
        request,
        %{observe: Sandbox.new!(fixtures)},
        max_capability_provider_requests: 1
      )

    assert result.status == "partial"
  end

  test "character and relationship writer playbooks cover all remaining Phase-6 families through Sandbox" do
    screenplay = PhaseSixFixture.screenplay()
    scene = hd(screenplay.ir.scenes)
    selection = %{"targets" => [%{"kind" => "scene", "id" => scene.id}]}

    character_specs = [
      CapabilityMeasurements.character_trajectory(),
      CapabilityMeasurements.agency_causality()
    ]

    character_fixtures =
      Map.new(character_specs, fn spec ->
        id = "capability:#{spec["id"]}:scene:#{scene.id}"
        {id, sandbox_answers(spec["questions"])}
      end)

    {:ok, character_packet} =
      Intelligence.run_capability_playbook(
        screenplay,
        "character_trajectory",
        %{
          "selection" => selection,
          "subject" => %{"character" => "Mara"},
          "story_world_records" => PhaseSixFixture.records(screenplay),
          "concern" => "Does Mara's choice trajectory remain legible?"
        },
        %{observe: Sandbox.new!(character_fixtures)}
      )

    assert Map.has_key?(character_packet.derived_state, "character_trajectory")
    assert Map.has_key?(character_packet.derived_state, "agency_causality")

    relationship_spec = CapabilityMeasurements.relationship_dynamics()

    relationship_provider =
      Sandbox.new!(%{
        "capability:relationship_dynamics:scene:#{scene.id}" =>
          sandbox_answers(relationship_spec["questions"])
      })

    {:ok, relationship_packet} =
      Intelligence.run_capability_playbook(
        screenplay,
        "relationship_pass",
        %{
          "selection" => selection,
          "subject" => %{"characters" => ["Mara", "Dan"]},
          "story_world_records" => PhaseSixFixture.records(screenplay),
          "concern" => "Track trust and leverage movement."
        },
        %{observe: relationship_provider}
      )

    assert Map.has_key?(relationship_packet.derived_state, "relationship_dynamics")
  end

  defp sandbox_answers(questions) do
    Map.new(questions, fn {key, question} ->
      value =
        case question.kind do
          :noul -> 0.9
          :choice -> sandbox_choice(question)
        end

      {to_string(key), value}
    end)
  end

  defp sandbox_choice(question) do
    labels = Enum.map(question.criteria, &elem(&1, 0))
    selected = hd(labels)
    remainder = if length(labels) > 1, do: 0.1 / (length(labels) - 1), else: 0.0
    probabilities = Map.new(labels, &{&1, if(&1 == selected, do: 0.9, else: remainder)})
    %{"probabilities" => probabilities, "choice" => selected, "confidence" => 0.9}
  end
end
