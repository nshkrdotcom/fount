from __future__ import annotations

import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
INTEL = ROOT / "packages" / "fount_intelligence"
OBSERVE = ROOT / "packages" / "fount_observe"


class PhaseFiveSourceTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_phase_five_source_surface_is_present(self) -> None:
        required = [
            "packages/fount_intelligence/lib/fount/intelligence/diagnosis.ex",
            "packages/fount_intelligence/lib/fount/intelligence/diagnosis/concern.ex",
            "packages/fount_intelligence/lib/fount/intelligence/diagnosis/evidence_need.ex",
            "packages/fount_intelligence/lib/fount/intelligence/diagnosis/result.ex",
            "packages/fount_intelligence/lib/fount/intelligence/acquisition/context_builder.ex",
            "packages/fount_intelligence/lib/fount/intelligence/acquisition/planner.ex",
            "packages/fount_intelligence/lib/fount/intelligence/acquisition/diagnostic_measurements.ex",
            "packages/fount_intelligence/lib/fount/intelligence/playbooks/writer_registry.ex",
            "packages/fount_intelligence/lib/fount/intelligence/playbooks/writer_runner.ex",
            "packages/fount_intelligence/lib/fount/intelligence/reporting/writer_packet.ex",
            "packages/fount_intelligence/lib/fount/intelligence/reporting/renderer.ex",
            "packages/fount_intelligence/guides/diagnosis-and-playbooks.md",
            "packages/fount_intelligence/examples/phase_five.exs",
            "packages/fount_intelligence/test/diagnosis_test.exs",
            "packages/fount_intelligence/test/writer_runner_test.exs",
        ]
        for path in required:
            self.assertTrue((ROOT / path).is_file(), path)

    def test_pure_diagnosis_has_no_effect_boundary_dependency(self) -> None:
        sources = [INTEL / "lib/fount/intelligence/diagnosis.ex"]
        sources += sorted((INTEL / "lib/fount/intelligence/diagnosis").glob("*.ex"))
        text = "\n".join(path.read_text(encoding="utf-8") for path in sources)
        forbidden = [
            "Fount.Observe",
            "SystemOneSDK",
            "Inference.",
            "ASM.",
            "Fount.Repo",
            "Fount.Persistence",
            "Fount.Intelligence.Acquisition",
            "Fount.Intelligence.Playbooks",
            "File.",
            "System.get_env",
            "DateTime.utc_now",
            "Fount.ID.v4",
        ]
        for token in forbidden:
            self.assertNotIn(token, text, token)

    def test_writer_registry_has_exact_phase_five_baseline(self) -> None:
        source = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/playbooks/writer_registry.ex"
        )
        ids = [
            "scene_doctor",
            "dialogue_pass",
            "character_trajectory",
            "relationship_pass",
            "suspense_audit",
            "sequence_momentum",
            "setup_payoff",
            "notes_diagnosis",
            "submission_read",
            "revision_regression",
        ]
        for playbook_id in ids:
            self.assertEqual(source.count(f'"id" => "{playbook_id}"'), 1, playbook_id)
        self.assertNotIn('"module" =>', source)
        self.assertNotIn('"function" =>', source)

    def test_diagnosis_lenses_are_closed_declarative_assets(self) -> None:
        relevance = json.loads(
            (OBSERVE / "priv/lenses/diagnosis.concern_relevance.json").read_text()
        )
        support = json.loads(
            (OBSERVE / "priv/lenses/diagnosis.evidence_support.json").read_text()
        )
        self.assertFalse(relevance["context_contract"]["allow_unknown"])
        self.assertFalse(support["context_contract"]["allow_unknown"])
        self.assertIn("concern", support["context_contract"]["required"])
        self.assertEqual(
            set(support["context_contract"]["optional"]),
            {"known_facts", "speaker_beliefs", "relationship_state", "base_assessments"},
        )
        serialized = json.dumps([relevance, support]).lower()
        for forbidden in ("api_key", "authorization", "base_url", "endpoint", "module", "function"):
            self.assertNotIn(forbidden, serialized)

    def test_writer_packet_keeps_semantic_layers_separate(self) -> None:
        source = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/reporting/writer_packet.ex"
        )
        for field in (
            "evidence",
            "derived_state",
            "diagnoses",
            "counterevidence",
            "alternatives",
            "strategies",
            "candidate",
            "resource_usage",
            "limitations",
        ):
            self.assertIn(f'{field}:', source)
        self.assertIn('"human_calibrated_response_estimate"', source)
        self.assertIn('human_calibration_required_for', source)

    def test_runner_has_required_multi_pass_order_and_cap_reporting(self) -> None:
        source = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/playbooks/writer_runner.ex"
        )
        order = [
            '"observe_base"',
            '"pure_evidence_need_reduction"',
            '"contextual_observe"',
            '"pure_diagnosis"',
        ]
        positions = [source.index(token) for token in order]
        self.assertEqual(positions, sorted(positions))
        self.assertIn("max_playbook_provider_requests", source)
        self.assertIn('"hosted_cost" => nil', source)
        self.assertIn('selection_complete = not plan["evidence_scope"]["truncated_by_host_limit"]', source)
        self.assertIn('status = if acquisition_complete and evidence_complete and selection_complete, do: "complete", else: "partial"', source)

    def test_phase_five_docs_make_no_runtime_or_human_validation_claim(self) -> None:
        guide = self.read("packages/fount_intelligence/guides/diagnosis-and-playbooks.md")
        self.assertIn("did not contain Elixir/Erlang/Mix", guide)
        self.assertIn("validation debt", guide)
        self.assertIn("No human usefulness or reader-agreement claim", guide)
        self.assertIn("Phase-6", guide)


if __name__ == "__main__":
    unittest.main()
