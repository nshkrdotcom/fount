from __future__ import annotations

import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
INTEL = ROOT / "packages" / "fount_intelligence"
OBSERVE = ROOT / "packages" / "fount_observe"


class PhaseSevenSourceTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_phase_seven_surface_is_present(self) -> None:
        required = [
            "packages/fount_intelligence/lib/fount/intelligence/capabilities/audience_reader_experience.ex",
            "packages/fount_intelligence/lib/fount/intelligence/capabilities/sequence_movement.ex",
            "packages/fount_intelligence/lib/fount/intelligence/capabilities/dialogue_interaction.ex",
            "packages/fount_intelligence/lib/fount/intelligence/capabilities/setup_payoff_motifs.ex",
            "packages/fount_intelligence/guides/capabilities-b.md",
            "packages/fount_intelligence/examples/phase_seven.exs",
            "packages/fount_intelligence/test/support/phase_seven_fixture.ex",
            "packages/fount_intelligence/test/phase_seven_capabilities_test.exs",
            "packages/fount_intelligence/test/phase_seven_runner_test.exs",
            "packages/fount_observe/test/phase_seven_lens_assets_test.exs",
        ]
        for path in required:
            self.assertTrue((ROOT / path).is_file(), path)

    def test_four_phase_seven_families_and_lenses_are_closed(self) -> None:
        ids = {
            "audience_reader_experience": "audience.reader_experience",
            "sequence_movement": "sequence.movement",
            "dialogue_interaction": "dialogue.exchange",
            "setup_payoff_motifs": "setup_payoff.motifs",
        }
        registry = self.read("packages/fount_observe/lib/fount/observe/registry.ex")
        measurements = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/acquisition/capability_measurements.ex"
        )
        capability_dispatch = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/capabilities.ex"
        )
        for family, lens_id in ids.items():
            self.assertIn(f'"{family}"', measurements)
            self.assertIn(f'"{family}"', capability_dispatch)
            self.assertIn(lens_id, registry)
            asset = json.loads((OBSERVE / "priv" / "lenses" / f"{lens_id}.json").read_text())
            self.assertFalse(asset["context_contract"]["allow_unknown"])
            self.assertEqual(asset["output_contract"], "observe.answer_set")
            self.assertNotIn("module", asset)
            self.assertNotIn("function", asset)

    def test_dialogue_context_contract_uses_only_installed_neutral_primitives(self) -> None:
        asset = json.loads(
            (OBSERVE / "priv" / "lenses" / "dialogue.exchange.json").read_text()
        )
        optional = asset["context_contract"]["optional"]
        self.assertEqual(optional["known_facts"], {"type": "list", "items": "fact"})
        self.assertEqual(optional["speaker_beliefs"], {"type": "list", "items": "belief"})
        self.assertEqual(optional["relationship_state"], {"type": "relation_summary"})
        self.assertEqual(optional["prior_turns"], {"type": "list", "items": "turn"})

        runner = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/playbooks/capability_runner.ex"
        )
        self.assertIn('ContextBuilder.validate("dialogue.exchange", slots)', runner)
        self.assertIn('"turn_pair"', runner)
        self.assertIn('"context_slot_names"', runner)

    def test_reader_family_uses_existing_strict_forward_reader(self) -> None:
        capability = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/capabilities/audience_reader_experience.ex"
        )
        runner = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/playbooks/capability_runner.ex"
        )
        self.assertIn("Reader.inspection_packet", capability)
        self.assertIn('"presentation_relative_forward_only"', capability)
        self.assertIn("Reader.reduce(model, events)", runner)
        self.assertNotIn("future_scene", capability)

    def test_sequence_and_setup_payoff_keep_temporal_dimensions_separate(self) -> None:
        sequence = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/capabilities/sequence_movement.ex"
        )
        setup = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/capabilities/setup_payoff_motifs.ex"
        )
        self.assertIn("Temporal.sequence_view", sequence)
        self.assertIn("ordering: :presentation", sequence)
        self.assertIn("ordering: :story_time", sequence)
        self.assertIn("Temporal.setup_payoff_ledger", setup)
        self.assertIn('"presentation_story_time_diverge"', setup)
        self.assertIn("StoryWorld.story_time_relation", setup)

    def test_writer_playbooks_cover_phase_seven_without_phase_eight(self) -> None:
        runner = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/playbooks/capability_runner.ex"
        )
        registry = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/playbooks/writer_registry.ex"
        )
        for playbook in ["suspense_audit", "sequence_momentum", "dialogue_pass", "setup_payoff"]:
            self.assertIn(f'"{playbook}"', runner)
        self.assertIn('"phase_7_capability_families"', registry)
        for phase_eight in [
            "emotional_value_movement",
            "theme_meaning",
            "genre_lens_packs",
            "revision_intelligence",
        ]:
            self.assertNotIn(f'"{phase_eight}" =>', runner)

    def test_pure_phase_seven_sources_have_no_effect_dependencies(self) -> None:
        names = [
            "audience_reader_experience.ex",
            "sequence_movement.ex",
            "dialogue_interaction.ex",
            "setup_payoff_motifs.ex",
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

    def test_no_runtime_or_human_qc_is_claimed_by_offline_delivery(self) -> None:
        guide = self.read("packages/fount_intelligence/guides/capabilities-b.md")
        self.assertIn("not run", guide.lower())
        self.assertIn("validation debt", guide.lower())
        self.assertIn("Phase 8", guide)
        self.assertIn("not implemented", guide)


if __name__ == "__main__":
    unittest.main()
