defmodule Fount.Intelligence.PhaseEightRunnerTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence
  alias Fount.Intelligence.Acquisition.CapabilityMeasurements
  alias Fount.Intelligence.Playbooks.CapabilityRunner
  alias Fount.Intelligence.TestSupport.PhaseEightFixture
  alias Fount.Observe.Sandbox

  test "existing character trajectory playbook keeps its Phase-6 default families" do
    assert CapabilityRunner.playbook_families()["character_trajectory"] ==
             ~w(character_trajectory agency_causality)
  end

  test "submission read can run Phase-8 theme analysis without generating candidate pages" do
    screenplay = PhaseEightFixture.screenplay()
    scenes = Enum.take(screenplay.ir.scenes, 2)
    spec = CapabilityMeasurements.theme_meaning()

    fixtures =
      Map.new(scenes, fn scene ->
        {"capability:theme_meaning:scene:#{scene.id}", sandbox_answers(spec["questions"])}
      end)

    assert {:ok, packet} =
             Intelligence.run_capability_playbook(
               screenplay,
               "submission_read",
               %{
                 "selection" => %{
                   "targets" => Enum.map(scenes, &%{"kind" => "scene", "id" => &1.id})
                 },
                 "story_world_records" => PhaseEightFixture.records(screenplay),
                 "intent" => %{
                   "theme_question" => "What does loyalty cost when it protects a lie?"
                 },
                 "concern" =>
                   "The ending may state its value conflict more clearly than the middle earns."
               },
               %{observe: Sandbox.new!(fixtures)}
             )

    assert packet.candidate == nil
    assert Map.has_key?(packet.derived_state, "theme_meaning")
    assert packet.provenance["phase"] == 8
  end

  test "revision regression compares explicit base and candidate revisions without accepting either" do
    before_model = PhaseEightFixture.screenplay()
    after_model = PhaseEightFixture.revised_screenplay()
    before_scene = List.last(before_model.ir.scenes)
    after_scene = List.last(after_model.ir.scenes)
    spec = CapabilityMeasurements.revision_intelligence()

    fixtures =
      [before_scene.id, after_scene.id]
      |> Enum.uniq()
      |> Map.new(fn scene_id ->
        {"capability:revision_intelligence:scene:#{scene_id}", sandbox_answers(spec["questions"])}
      end)

    assert {:ok, packet} =
             Intelligence.run_revision_playbook(
               before_model,
               after_model,
               %{
                 "before_selection" => %{
                   "targets" => [%{"kind" => "scene", "id" => before_scene.id}]
                 },
                 "after_selection" => %{
                   "targets" => [%{"kind" => "scene", "id" => after_scene.id}]
                 },
                 "before_story_world_records" => PhaseEightFixture.records(before_model),
                 "after_story_world_records" => PhaseEightFixture.records(after_model),
                 "intended_effect" =>
                   "Make Mara's final choice more active while preserving the watch's private history.",
                 "protected_strengths" => ["The watch remains emotionally meaningful"],
                 "concern" =>
                   "Does the new handoff gain agency without flattening the Mara/Dan relationship?"
               },
               %{observe: Sandbox.new!(fixtures)}
             )

    assert packet.candidate == nil
    assert packet.revision_comparison["lineage"]["before_revision_id"] == before_model.revision.id
    assert packet.revision_comparison["lineage"]["after_revision_id"] == after_model.revision.id
    assert packet.revision_comparison["presentation_vs_diegetic"]["kept_separate"]
    assert packet.provenance["phase"] == 8
  end

  defp sandbox_answers(questions) do
    Map.new(questions, fn {key, question} ->
      value =
        case question.kind do
          :noul -> 0.9
          :choice -> sandbox_choice(question)
          :score -> 0
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
