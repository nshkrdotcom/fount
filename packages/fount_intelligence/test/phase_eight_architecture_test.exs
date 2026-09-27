defmodule Fount.Intelligence.PhaseEightArchitectureTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.Capabilities

  test "all twelve capability families are installed and Phase 9 remains outside the capability layer" do
    assert Capabilities.families() == [
             "scene_engine",
             "agency_causality",
             "character_trajectory",
             "relationship_dynamics",
             "audience_reader_experience",
             "sequence_movement",
             "dialogue_interaction",
             "setup_payoff_motifs",
             "emotional_value_movement",
             "theme_meaning",
             "genre_lens_packs",
             "revision_intelligence"
           ]

    refute Capabilities.member?("workshop_intelligence_integration")
  end

  test "Phase-8 pure capability modules do not acquire, persist, generate or read runtime state" do
    root = Path.expand("../lib/fount/intelligence/capabilities", __DIR__)

    sources =
      ~w(emotional_value_movement theme_meaning genre_lens_packs revision_intelligence)
      |> Enum.map_join("\n", fn name -> File.read!(Path.join(root, name <> ".ex")) end)

    for forbidden <- [
          "SystemOneSDK",
          "Inference.",
          "ASM.",
          "Fount.Repo",
          "Fount.Persistence",
          "Fount.Intelligence.Acquisition",
          "Fount.Intelligence.Playbooks",
          "System.get_env",
          "DateTime.utc_now",
          "Fount.ID.v4"
        ] do
      refute String.contains?(sources, forbidden)
    end
  end
end
