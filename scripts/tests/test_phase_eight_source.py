from __future__ import annotations

import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
INTEL = ROOT / "packages" / "fount_intelligence"
OBSERVE = ROOT / "packages" / "fount_observe"


class PhaseEightSourceTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_phase_eight_surface_is_present(self) -> None:
        required = [
            "packages/fount_intelligence/lib/fount/intelligence/capabilities/emotional_value_movement.ex",
            "packages/fount_intelligence/lib/fount/intelligence/capabilities/theme_meaning.ex",
            "packages/fount_intelligence/lib/fount/intelligence/capabilities/genre_lens_packs.ex",
            "packages/fount_intelligence/lib/fount/intelligence/capabilities/revision_intelligence.ex",
            "packages/fount_intelligence/lib/fount/intelligence/packs.ex",
            "packages/fount_intelligence/lib/fount/intelligence/packs/catalog.ex",
            "packages/fount_intelligence/lib/fount/intelligence/packs/genre_pack.ex",
            "packages/fount_observe/lib/fount/observe/declarative_lens.ex",
            "packages/fount_intelligence/guides/capabilities-c.md",
            "packages/fount_observe/guides/declarative-lenses.md",
            "packages/fount_intelligence/examples/phase_eight.exs",
            "packages/fount_intelligence/test/phase_eight_architecture_test.exs",
            "packages/fount_intelligence/test/phase_eight_capabilities_test.exs",
            "packages/fount_intelligence/test/phase_eight_packs_test.exs",
            "packages/fount_intelligence/test/phase_eight_runner_test.exs",
            "packages/fount_observe/test/phase_eight_lens_assets_test.exs",
        ]
        for path in required:
            self.assertTrue((ROOT / path).is_file(), path)

    def test_all_twelve_families_are_installed(self) -> None:
        measurements = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/acquisition/capability_measurements.ex"
        )
        dispatch = self.read("packages/fount_intelligence/lib/fount/intelligence/capabilities.ex")
        ids = [
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
            "revision_intelligence",
        ]
        for family in ids:
            self.assertIn(f'"{family}"', measurements)
            self.assertIn(f'"{family}"', dispatch)
        self.assertNotIn('"workshop_intelligence_integration"', dispatch)

    def test_phase_eight_lenses_are_closed_json_assets(self) -> None:
        registry = self.read("packages/fount_observe/lib/fount/observe/registry.ex")
        for lens_id in [
            "emotional.value_movement",
            "theme.meaning",
            "genre.lens_pack",
            "revision.intelligence",
        ]:
            self.assertIn(lens_id, registry)
            asset = json.loads((OBSERVE / "priv" / "lenses" / f"{lens_id}.json").read_text())
            self.assertFalse(asset["context_contract"]["allow_unknown"])
            self.assertEqual(asset["output_contract"], "observe.answer_set")
            for forbidden in ["module", "function", "endpoint", "credentials", "tool"]:
                self.assertNotIn(forbidden, asset)

    def test_emotional_family_is_multidimensional_without_universal_score(self) -> None:
        source = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/capabilities/emotional_value_movement.ex"
        )
        measurements = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/acquisition/capability_measurements.ex"
        )
        for dimension in [
            "hope_direction",
            "fear_direction",
            "security_direction",
            "belonging_direction",
            "trust_direction",
            "status_direction",
            "control_direction",
            "certainty_direction",
            "moral_confidence_direction",
        ]:
            self.assertIn(dimension, source)
            self.assertIn(dimension, measurements)
        self.assertNotIn('"emotion_score"', source)
        self.assertIn("do not claim a universal human emotion", source)

    def test_theme_keeps_hypotheses_counterevidence_and_no_depth_score(self) -> None:
        source = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/capabilities/theme_meaning.ex"
        )
        self.assertIn('"thematic_hypotheses"', source)
        self.assertIn('"counterevidence_scene_ids"', source)
        self.assertIn('"writer_intent_comparison"', source)
        self.assertNotIn('"depth_score" =>', source)
        self.assertNotIn('"theme_score" =>', source)

    def test_genre_pack_workflow_is_data_only_with_six_initial_core_assets(self) -> None:
        packs = self.read("packages/fount_intelligence/lib/fount/intelligence/packs.ex")
        validator = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/packs/genre_pack.ex"
        )
        for pack_id in [
            "genre.mystery",
            "genre.thriller",
            "genre.horror",
            "genre.romance",
            "genre.comedy",
            "genre.action",
        ]:
            self.assertIn(f'"{pack_id}"', packs)
        for token in [
            "module",
            "function",
            "shell",
            "path",
            "endpoint",
            "credentials",
            "database",
            "callback",
            "decoder",
            "tool",
        ]:
            self.assertIn(token, validator)
        self.assertIn('"subversions"', packs)
        self.assertIn("resource_policy", validator)
        runner = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/playbooks/capability_runner.ex"
        )
        self.assertIn('Map.get(request, "custom_lenses", %{})', runner)
        self.assertIn("custom_lenses: custom_lenses", runner)

    def test_declarative_lens_compiles_only_to_existing_observe_question_and_lens(self) -> None:
        source = self.read("packages/fount_observe/lib/fount/observe/declarative_lens.ex")
        self.assertIn("Question.noul", source)
        self.assertIn("Question.choice", source)
        self.assertIn("Question.score", source)
        self.assertIn("Lens.validate", source)
        self.assertIn("Registry.projection?", source)
        self.assertIn('"sensor" => "system_one"', source)
        self.assertNotIn("Code.eval", source)
        self.assertNotIn("Module.concat", source)

    def test_revision_intelligence_keeps_presentation_diegetic_story_time_separate(self) -> None:
        source = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/capabilities/revision_intelligence.ex"
        )
        for key in [
            '"presentation_effects"',
            '"diegetic_state_effects"',
            '"story_time_effects"',
            '"causal_ripple"',
            '"target_effect"',
            '"protected_strengths"',
            '"strategy_distinctness"',
            '"character_trajectory_diff"',
            '"relationship_trajectory_diff"',
        ]:
            self.assertIn(key, source)
        self.assertIn("does not decide whether the revision is better", source)

    def test_existing_character_trajectory_default_is_preserved(self) -> None:
        runner = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/playbooks/capability_runner.ex"
        )
        self.assertIn(
            '"character_trajectory" => ~w(character_trajectory agency_causality),', runner
        )
        self.assertIn(
            'extra_families("character_trajectory", %{"include_emotional_value_movement" => true})',
            runner,
        )

    def test_pure_phase_eight_sources_have_no_effect_dependencies(self) -> None:
        names = [
            "emotional_value_movement.ex",
            "theme_meaning.ex",
            "genre_lens_packs.ex",
            "revision_intelligence.ex",
        ]
        text = "\n".join(
            (INTEL / "lib/fount/intelligence/capabilities" / name).read_text(encoding="utf-8")
            for name in names
        )
        forbidden = [
            "SystemOneSDK",
            "Inference.",
            "ASM.",
            "Fount.Repo",
            "Fount.Persistence",
            "Fount.Intelligence.Acquisition",
            "Fount.Intelligence.Playbooks",
            "System.get_env",
            "DateTime.utc_now",
            "Fount.ID.v4",
        ]
        for token in forbidden:
            self.assertNotIn(token, text, token)

    def test_phase_nine_is_not_implemented_or_claimed(self) -> None:
        guide = self.read("packages/fount_intelligence/guides/capabilities-c.md")
        self.assertIn("stop before Phase 9", guide)
        self.assertIn("not run here", guide.lower())
        self.assertIn("validation debt", guide.lower())
        workshop = self.read("packages/fount_workshop/lib/fount_workshop.ex")
        self.assertNotIn("Phase 9", workshop)


if __name__ == "__main__":
    unittest.main()
