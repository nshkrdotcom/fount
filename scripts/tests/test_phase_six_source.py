from __future__ import annotations

import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
INTEL = ROOT / "packages" / "fount_intelligence"
OBSERVE = ROOT / "packages" / "fount_observe"


class PhaseSixSourceTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_phase_six_surface_is_present(self) -> None:
        required = [
            "packages/fount_intelligence/lib/fount/intelligence/capabilities.ex",
            "packages/fount_intelligence/lib/fount/intelligence/capabilities/result.ex",
            "packages/fount_intelligence/lib/fount/intelligence/capabilities/support.ex",
            "packages/fount_intelligence/lib/fount/intelligence/capabilities/scene_engine.ex",
            "packages/fount_intelligence/lib/fount/intelligence/capabilities/agency_causality.ex",
            "packages/fount_intelligence/lib/fount/intelligence/capabilities/character_trajectory.ex",
            "packages/fount_intelligence/lib/fount/intelligence/capabilities/relationship_dynamics.ex",
            "packages/fount_intelligence/lib/fount/intelligence/acquisition/capability_measurements.ex",
            "packages/fount_intelligence/lib/fount/intelligence/playbooks/capability_runner.ex",
            "packages/fount_intelligence/guides/capabilities-a.md",
            "packages/fount_intelligence/examples/phase_six.exs",
            "packages/fount_intelligence/test/support/phase_six_fixture.ex",
            "packages/fount_intelligence/test/phase_six_capabilities_test.exs",
            "packages/fount_intelligence/test/phase_six_runner_test.exs",
            "packages/fount_observe/test/phase_six_lens_assets_test.exs",
        ]
        for path in required:
            self.assertTrue((ROOT / path).is_file(), path)

    def test_four_capability_families_and_lenses_are_closed(self) -> None:
        ids = {
            "scene_engine": "scene.engine",
            "agency_causality": "agency.causality",
            "character_trajectory": "character.trajectory",
            "relationship_dynamics": "relationship.dynamics",
        }
        registry = self.read("packages/fount_observe/lib/fount/observe/registry.ex")
        measurements = self.read("packages/fount_intelligence/lib/fount/intelligence/acquisition/capability_measurements.ex")
        for family, lens_id in ids.items():
            self.assertIn(f'"{family}"', measurements)
            self.assertIn(lens_id, registry)
            asset = json.loads((OBSERVE / "priv" / "lenses" / f"{lens_id}.json").read_text())
            self.assertFalse(asset["context_contract"]["allow_unknown"])
            self.assertEqual(asset["output_contract"], "observe.answer_set")
            self.assertNotIn("module", asset)
            self.assertNotIn("function", asset)

    def test_pure_capability_source_has_no_effect_dependencies(self) -> None:
        sources = sorted((INTEL / "lib/fount/intelligence/capabilities").glob("*.ex"))
        text = "\n".join(path.read_text(encoding="utf-8") for path in sources)
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

    def test_source_excerpts_are_semantic_measurement_input(self) -> None:
        runner = self.read("packages/fount_intelligence/lib/fount/intelligence/playbooks/capability_runner.ex")
        self.assertIn('"source" => Enum.map(evidence', runner)
        self.assertIn('"evidence" => evidence', runner)
        self.assertIn('"source_truncated_for_host_limit"', runner)
        self.assertIn('combined_status', runner)

    def test_character_and_relationship_keep_non_linear_semantics(self) -> None:
        character = self.read("packages/fount_intelligence/lib/fount/intelligence/capabilities/character_trajectory.ex")
        relationship = self.read("packages/fount_intelligence/lib/fount/intelligence/capabilities/relationship_dynamics.ex")
        self.assertIn('"reader_visible_presentation"', character)
        self.assertIn('"diegetic_state_changes"', character)
        self.assertIn('"No transformation arc is required', character)
        self.assertIn('"directional_state"', relationship)
        self.assertIn('"asymmetric_state"', relationship)
        self.assertIn('"non_linear_presentation"', relationship)

    def test_catalog_exit_outputs_are_present(self) -> None:
        scene = self.read("packages/fount_intelligence/lib/fount/intelligence/capabilities/scene_engine.ex")
        agency = self.read("packages/fount_intelligence/lib/fount/intelligence/capabilities/agency_causality.ex")
        relationship = self.read("packages/fount_intelligence/lib/fount/intelligence/capabilities/relationship_dynamics.ex")
        runner_test = self.read("packages/fount_intelligence/test/phase_six_runner_test.exs")
        self.assertIn('"turn_candidates"', scene)
        self.assertIn('"surrounding_sequence_contribution"', scene)
        self.assertIn('"consequence_latency"', agency)
        self.assertIn('defp parties(', relationship)
        self.assertIn('character and relationship writer playbooks cover all remaining Phase-6 families through Sandbox', runner_test)


    def test_docs_do_not_claim_unrun_runtime_or_human_checks(self) -> None:
        guide = self.read("packages/fount_intelligence/guides/capabilities-a.md")
        self.assertIn("Elixir/Erlang/Mix were unavailable", guide)
        self.assertIn("not claimed", guide)
        self.assertIn("validation debt", guide)
        self.assertIn("not Phase-9 integration", guide)


if __name__ == "__main__":
    unittest.main()
