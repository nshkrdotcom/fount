defmodule Fount.Intelligence.PhaseSevenArchitectureTest do
  use ExUnit.Case, async: true

  test "Phase-7 pure capability modules do not acquire, persist, generate, or read runtime state" do
    root = Path.expand("../lib/fount/intelligence/capabilities", __DIR__)

    sources =
      ~w(audience_reader_experience sequence_movement dialogue_interaction setup_payoff_motifs)
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

  test "Phase-7 capability catalog stops before Phase-8 families" do
    assert Fount.Intelligence.Capabilities.families() == [
             "scene_engine",
             "agency_causality",
             "character_trajectory",
             "relationship_dynamics",
             "audience_reader_experience",
             "sequence_movement",
             "dialogue_interaction",
             "setup_payoff_motifs"
           ]

    refute Fount.Intelligence.Capabilities.member?("emotional_value_movement")
    refute Fount.Intelligence.Capabilities.member?("theme_meaning")
    refute Fount.Intelligence.Capabilities.member?("genre_lens_packs")
    refute Fount.Intelligence.Capabilities.member?("revision_intelligence")
  end
end
