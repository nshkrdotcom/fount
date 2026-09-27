defmodule Fount.Intelligence.PhaseSevenRunnerTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence
  alias Fount.Intelligence.Acquisition.CapabilityMeasurements
  alias Fount.Intelligence.TestSupport.PhaseSevenFixture
  alias Fount.Observe.Sandbox

  test "suspense audit uses supplied strict-forward reader events and returns no candidate pages" do
    screenplay = PhaseSevenFixture.screenplay()
    scene = hd(screenplay.ir.scenes)
    spec = CapabilityMeasurements.audience_reader_experience()

    provider =
      Sandbox.new!(%{
        "capability:audience_reader_experience:scene:#{scene.id}" =>
          sandbox_answers(spec["questions"])
      })

    {:ok, packet} =
      Intelligence.run_capability_playbook(
        screenplay,
        "suspense_audit",
        %{
          "selection" => %{"targets" => [%{"kind" => "scene", "id" => scene.id}]},
          "story_world_records" => PhaseSevenFixture.records(screenplay),
          "reader_events" => PhaseSevenFixture.reader_events(screenplay),
          "concern" =>
            "Does the first watch clue create a useful question without leaking the answer?"
        },
        %{observe: provider}
      )

    assert packet.candidate == nil
    assert Map.has_key?(packet.derived_state, "audience_reader_experience")
    assert packet.provenance["phase"] == 7
  end

  test "sequence momentum exposes movement state across a selected run of scenes" do
    screenplay = PhaseSevenFixture.screenplay()
    scenes = Enum.take(screenplay.ir.scenes, 3)
    spec = CapabilityMeasurements.sequence_movement()

    fixtures =
      Map.new(scenes, fn scene ->
        {"capability:sequence_movement:scene:#{scene.id}", sandbox_answers(spec["questions"])}
      end)

    {:ok, packet} =
      Intelligence.run_capability_playbook(
        screenplay,
        "sequence_momentum",
        %{
          "selection" => %{"targets" => Enum.map(scenes, &%{"kind" => "scene", "id" => &1.id})},
          "story_world_records" => PhaseSevenFixture.records(screenplay),
          "concern" => "Does the watch sequence transform rather than repeat?"
        },
        %{observe: Sandbox.new!(fixtures)}
      )

    assert Map.has_key?(packet.derived_state, "sequence_movement")
    assert packet.coverage["complete"]
  end

  test "dialogue pass measures adjacent canonical dialogue turns with validated typed context" do
    screenplay = PhaseSevenFixture.screenplay()
    scene = Enum.at(screenplay.ir.scenes, 2)
    dialogue_spec = CapabilityMeasurements.dialogue_interaction()
    relationship_spec = CapabilityMeasurements.relationship_dynamics()

    dialogue_fixtures =
      Map.new(1..3, fn ordinal ->
        {"capability:dialogue_interaction:scene:#{scene.id}:pair:#{ordinal}",
         sandbox_answers(dialogue_spec["questions"])}
      end)

    fixtures =
      Map.put(
        dialogue_fixtures,
        "capability:relationship_dynamics:scene:#{scene.id}",
        sandbox_answers(relationship_spec["questions"])
      )

    {:ok, packet} =
      Intelligence.run_capability_playbook(
        screenplay,
        "dialogue_pass",
        %{
          "selection" => %{"targets" => [%{"kind" => "scene", "id" => scene.id}]},
          "subject" => %{"characters" => ["Mara", "Dan"]},
          "story_world_records" => PhaseSevenFixture.records(screenplay),
          "dialogue_context" => %{
            "speaker_beliefs" => [
              %{
                "owner" => "Mara",
                "proposition" => "Dan knows what D.R. means",
                "stance" => "believes",
                "probability" => 0.9
              }
            ],
            "prior_turns" => [
              %{
                "speaker" => "Mara",
                "text" => "You said you threw it out.",
                "channel" => "dialogue"
              }
            ]
          },
          "concern" =>
            "The corridor exchange may repeat the same pressure instead of changing leverage."
        },
        %{observe: Sandbox.new!(fixtures)}
      )

    dialogue = packet.derived_state["dialogue_interaction"]
    assert length(dialogue["turn_pair_observations"]) == 3
    assert dialogue["context_usage"]["slot_names"] == ["prior_turns", "speaker_beliefs"]
    assert Map.has_key?(packet.derived_state, "relationship_dynamics")
  end

  test "dialogue context rejects unknown slots before provider dispatch" do
    screenplay = PhaseSevenFixture.screenplay()
    scene = Enum.at(screenplay.ir.scenes, 2)

    assert {:error, _} =
             Intelligence.preflight_capability(
               screenplay,
               "dialogue_interaction",
               %{
                 "selection" => %{"targets" => [%{"kind" => "scene", "id" => scene.id}]},
                 "story_world_records" => PhaseSevenFixture.records(screenplay),
                 "dialogue_context" => %{"future_intelligence_struct" => %{"invented" => true}}
               }
             )
  end

  test "setup/payoff playbook retains non-linear presentation versus story-time qualification" do
    screenplay = PhaseSevenFixture.screenplay()
    scenes = Enum.take(screenplay.ir.scenes, 2)
    spec = CapabilityMeasurements.setup_payoff_motifs()

    fixtures =
      Map.new(scenes, fn scene ->
        {"capability:setup_payoff_motifs:scene:#{scene.id}", sandbox_answers(spec["questions"])}
      end)

    {:ok, packet} =
      Intelligence.run_capability_playbook(
        screenplay,
        "setup_payoff",
        %{
          "selection" => %{"targets" => Enum.map(scenes, &%{"kind" => "scene", "id" => &1.id})},
          "story_world_records" => PhaseSevenFixture.records(screenplay),
          "concern" =>
            "Does the flashback clarify the watch without pretending it happened later?"
        },
        %{observe: Sandbox.new!(fixtures)}
      )

    lifecycle = packet.derived_state["setup_payoff_motifs"]["setup_payoff_lifecycle"]

    assert Enum.any?(lifecycle, fn item ->
             Enum.any?(item["payoffs"] || [], & &1["presentation_story_time_diverge"])
           end)
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
