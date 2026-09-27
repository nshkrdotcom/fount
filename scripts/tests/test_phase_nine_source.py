from __future__ import annotations

import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class PhaseNineSourceTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_phase_nine_bridge_and_tests_are_present(self) -> None:
        required = [
            "packages/fount_workshop/lib/fount_workshop/writing/intelligence.ex",
            "packages/fount_workshop/test/phase_nine_intelligence_test.exs",
            "packages/fount_workshop/guides/intelligence-integration.md",
        ]
        for path in required:
            self.assertTrue((ROOT / path).is_file(), path)

    def test_workshop_uses_existing_intelligence_public_apis(self) -> None:
        source = self.read(
            "packages/fount_workshop/lib/fount_workshop/writing/intelligence.ex"
        )
        for call in [
            "Fount.Intelligence.preflight_capability_playbook",
            "Fount.Intelligence.run_capability_playbook",
            "Fount.Intelligence.run_revision_playbook",
            "WriterPacket.to_map",
        ]:
            self.assertIn(call, source)
        for invented in [
            "SystemOneSDK.",
            "ASM.",
            "Inference.complete",
            "Fount.Intelligence.accept",
            "Fount.Intelligence.rank",
        ]:
            self.assertNotIn(invented, source)

    def test_analysis_remains_optional_for_existing_writing_services(self) -> None:
        session = self.read("packages/fount_workshop/lib/fount_workshop/session.ex")
        bridge = self.read(
            "packages/fount_workshop/lib/fount_workshop/writing/intelligence.ex"
        )
        self.assertIn(
            "defp services(%{store: %Store{}, inference: %Inference.Client{}})", session
        )
        self.assertIn('"observe_provider_not_configured"', bridge)
        self.assertIn('"status" => "not_run"', bridge)

    def test_preflight_is_provider_free_and_persisted_before_execution(self) -> None:
        bridge = self.read(
            "packages/fount_workshop/lib/fount_workshop/writing/intelligence.ex"
        )
        session = self.read("packages/fount_workshop/lib/fount_workshop/session.ex")
        self.assertIn("preflight_capability_playbook", bridge)
        self.assertIn('"phase9_preflight" => preflight', session)
        self.assertIn('"changes_canon" => false', session)

    def test_pre_and_post_writer_packets_are_kept_separate_from_candidate_pages(self) -> None:
        generation = self.read(
            "packages/fount_workshop/lib/fount_workshop/writing/generation.ex"
        )
        candidate = self.read("packages/fount_workshop/lib/fount_workshop/candidate.ex")
        review = self.read("packages/fount_workshop/lib/fount_workshop/review.ex")
        self.assertIn(":intelligence_lineage", generation)
        self.assertIn('"revision_intelligence"', candidate)
        self.assertIn('"writer_packet"', review)
        self.assertIn('"revision_packet"', review)
        self.assertIn('"resource_usage"', review)

    def test_notes_do_not_collapse_reaction_cause_and_treatment(self) -> None:
        bridge = self.read(
            "packages/fount_workshop/lib/fount_workshop/writing/intelligence.ex"
        )
        for key in [
            '"reaction"',
            '"suggested_cause"',
            '"suggested_treatment"',
            '"raw_note"',
        ]:
            self.assertIn(key, bridge)
        self.assertIn("reported_reaction_possible_cause_possible_treatment", bridge)

    def test_strategy_and_propagation_lineage_are_writer_reviewable(self) -> None:
        strategy = self.read("packages/fount_workshop/lib/fount_workshop/strategy.ex")
        bridge = self.read(
            "packages/fount_workshop/lib/fount_workshop/writing/intelligence.ex"
        )
        review = self.read("packages/fount_workshop/lib/fount_workshop/review.ex")
        self.assertIn("strategies_not_distinct", strategy)
        self.assertIn('"diagnosis_ids"', bridge)
        self.assertIn('"consequence_proposals"', bridge)
        self.assertIn('"causal_ripple"', review)

    def test_revision_checks_are_advisory_and_review_gate_is_unchanged(self) -> None:
        bridge = self.read(
            "packages/fount_workshop/lib/fount_workshop/writing/intelligence.ex"
        )
        gate = self.read("packages/fount/lib/fount/writing/review_gate.ex")
        self.assertIn('"severity" => "advisory"', bridge)
        self.assertIn('required = check["severity"] == "required"', gate)
        self.assertNotIn("revision_intelligence", gate)

    def test_phase_ten_is_not_added(self) -> None:
        workshop = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (ROOT / "packages" / "fount_workshop").rglob("*.ex")
        )
        self.assertNotIn("Phase-10", workshop)
        self.assertNotIn("Phase 10", workshop)


if __name__ == "__main__":
    unittest.main()
