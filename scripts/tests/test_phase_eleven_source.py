from __future__ import annotations

import hashlib
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class PhaseElevenSourceTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_evaluation_surface_and_shipped_assets_exist(self) -> None:
        required = [
            "packages/fount_intelligence/lib/fount/intelligence/evaluation.ex",
            "packages/fount_intelligence/lib/fount/intelligence/evaluation/corpus_manifest.ex",
            "packages/fount_intelligence/lib/fount/intelligence/evaluation/annotation.ex",
            "packages/fount_intelligence/lib/fount/intelligence/evaluation/metrics.ex",
            "packages/fount_intelligence/lib/fount/intelligence/evaluation/drift.ex",
            "packages/fount_intelligence/lib/fount/intelligence/evaluation/benchmark.ex",
            "packages/fount_intelligence/lib/fount/intelligence/evaluation/resources.ex",
            "packages/fount_intelligence/lib/fount/intelligence/evaluation/suite.ex",
            "packages/fount_intelligence/priv/evaluation/corpus_manifest.synthetic.json",
            "packages/fount_intelligence/priv/evaluation/frozen_concealment_fixture.json",
            "packages/fount_intelligence/priv/evaluation/nonlinear_story_time.synthetic.json",
            "packages/fount_intelligence/priv/evaluation/phase_eleven_suite.json",
            "packages/fount_intelligence/priv/evaluation/reader_annotations.synthetic.json",
        ]
        for path in required:
            self.assertTrue((ROOT / path).is_file(), path)

    def test_corpus_policy_is_rights_specific_and_secret_keys_fail_closed(self) -> None:
        source = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/evaluation/corpus_manifest.ex"
        )
        self.assertIn("observe_hosted", source)
        self.assertIn("inference_hosted", source)
        self.assertIn("provider_export_allowed", source)
        self.assertIn("human_review_allowed", source)
        self.assertIn("redistribution_allowed", source)
        self.assertIn("@secret_fragments", source)
        self.assertNotIn("Code.eval", source)
        self.assertNotIn("Module.concat", source)

    def test_human_labels_are_semantic_and_disagreement_is_retained(self) -> None:
        source = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/evaluation/annotation.ex"
        )
        self.assertIn('"label_distribution"', source)
        self.assertIn('"annotations" => validated', source)
        self.assertIn("first_exposure", source)
        self.assertIn("@forbidden_fragments", source)

    def test_metrics_include_calibration_abstention_and_ordinal_error(self) -> None:
        source = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/evaluation/metrics.ex"
        )
        for token in [
            '"brier_score"',
            '"log_loss"',
            '"expected_calibration_error"',
            '"abstention"',
            '"ordinal_mean_absolute_error"',
        ]:
            self.assertIn(token, source)

    def test_frozen_fixture_pins_current_output_contract_and_has_no_compat_decoder(self) -> None:
        source = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/evaluation/benchmark.ex"
        )
        self.assertIn("OutputContract.validate", source)
        self.assertIn("stale_output_contract_fixture", source)
        self.assertIn('"regeneration_required" => true', source)
        self.assertIn('"compatibility_decode" => false', source)
        self.assertNotIn("decode_old", source)
        fixture = json.loads(
            self.read("packages/fount_intelligence/priv/evaluation/frozen_concealment_fixture.json")
        )
        self.assertEqual(fixture["output_contract"]["id"], "observe.distribution")
        self.assertEqual(len(fixture["output_contract"]["sha256"]), 64)
        self.assertEqual(
            fixture["measurement_result"]["output_contract_sha256"],
            fixture["output_contract"]["sha256"],
        )
        shape_bytes = json.dumps(
            fixture["output_contract"]["shape"],
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
        ).encode("utf-8")
        self.assertEqual(
            hashlib.sha256(shape_bytes).hexdigest(),
            fixture["output_contract"]["sha256"],
        )
        fixture_body = dict(fixture)
        stored_fixture_sha = fixture_body.pop("fixture_sha256")
        fixture_bytes = json.dumps(
            fixture_body, sort_keys=True, separators=(",", ":"), ensure_ascii=False
        ).encode("utf-8")
        self.assertEqual(hashlib.sha256(fixture_bytes).hexdigest(), stored_fixture_sha)

    def test_all_capability_families_are_in_evaluation_suite(self) -> None:
        suite = json.loads(
            self.read("packages/fount_intelligence/priv/evaluation/phase_eleven_suite.json")
        )
        self.assertEqual(len(suite["capability_families"]), 12)
        self.assertEqual(len(set(suite["capability_families"])), 12)
        self.assertTrue(suite["support_validity"])
        self.assertEqual(suite["writer_usefulness"], "separate_optional_study")

    def test_live_qc_paths_use_existing_boundaries_and_small_workshop_scope(self) -> None:
        workshop = self.read(
            "packages/fount_workshop/lib/fount_workshop/live_example.ex"
        )
        self.assertIn('"phase_eleven_qc"', workshop)
        self.assertIn('Map.put("alternatives", 1)', workshop)
        self.assertIn('Launcher.clients(observe: mode != "phase_eleven_qc")', workshop)
        self.assertIn("max_inference_calls = if mode == \"phase_eleven_qc\", do: 8", workshop)
        observe_live = self.read("packages/fount_observe/examples/phase_eleven_live.exs")
        workshop_live = self.read("packages/fount_workshop/examples/phase_eleven_live.exs")
        self.assertIn("FOUNT_PHASE11_OBSERVE_LIVE", observe_live)
        self.assertIn("FOUNT_PHASE11_WORKSHOP_LIVE", workshop_live)
        self.assertNotIn('cache:', observe_live)
        self.assertIn('accept_demo: false', workshop_live)
        self.assertIn('"repeatability_drift" => drift', observe_live)

        intelligence = "\n".join(
            self.read(path)
            for path in [
                "packages/fount_intelligence/lib/fount/intelligence/evaluation.ex",
                "packages/fount_intelligence/lib/fount/intelligence/evaluation/benchmark.ex",
                "packages/fount_intelligence/lib/fount/intelligence/evaluation/drift.ex",
            ]
        )
        for direct in ["SystemOneSDK.", "Inference.", "ASM."]:
            self.assertNotIn(direct, intelligence)


    def test_robustness_and_longitudinal_regressions_are_executable(self) -> None:
        robustness = self.read("packages/fount_observe/test/executor_sandbox_test.exs")
        phase_two = self.read("packages/fount_observe/test/phase_two_execution_test.exs")
        history = self.read(
            "packages/fount_intelligence/integration/phase_eleven_resource_history_test.exs"
        )
        self.assertIn("missing associations never become negative evidence", robustness)
        self.assertIn("exhausted budget remain explicit acquisition errors", robustness)
        self.assertIn("credential-like transport extras are rejected", phase_two)
        self.assertIn("durable analysis history can calibrate preflight estimates", history)
        self.assertIn("summarize_resource_history", history)

    def test_no_phase_twelve_implementation_is_introduced(self) -> None:
        changed_roots = [
            ROOT / "packages" / "fount_intelligence" / "lib" / "fount" / "intelligence" / "evaluation",
            ROOT / "packages" / "fount_intelligence" / "priv" / "evaluation",
        ]
        text = "\n".join(
            path.read_text(encoding="utf-8")
            for root in changed_roots
            for path in root.rglob("*")
            if path.is_file()
        )
        self.assertNotIn("Phase 12", text)
        self.assertNotIn("W01", text)
        self.assertNotIn("fragment-to-scene", text)


if __name__ == "__main__":
    unittest.main()
