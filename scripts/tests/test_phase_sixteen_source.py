from __future__ import annotations

import importlib.util
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "final_acceptance.py"
SPEC = importlib.util.spec_from_file_location("fount_final_acceptance", MODULE_PATH)
assert SPEC and SPEC.loader
acceptance = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(acceptance)


class PhaseSixteenSourceTests(unittest.TestCase):
    def test_final_source_audit_passes(self) -> None:
        report = acceptance.audit()
        failures = [item for item in report["checks"] if item["status"] != "pass"]
        self.assertEqual(failures, [], failures)
        self.assertEqual(report["status"], "pass")

    def test_all_workflows_and_acceptance_scenarios_have_owned_evidence(self) -> None:
        self.assertEqual(set(acceptance.WORKFLOW_EVIDENCE), {f"W{i:02d}" for i in range(1, 13)})
        self.assertEqual(set(acceptance.SCENARIO_EVIDENCE), {f"A{i:02d}" for i in range(1, 13)})
        for path in set(acceptance.WORKFLOW_EVIDENCE.values()) | set(acceptance.SCENARIO_EVIDENCE.values()):
            self.assertTrue((ROOT / path).is_file(), path)

    def test_machine_readable_matrix_is_complete_and_unexecuted(self) -> None:
        matrix_path = ROOT / "packages" / "fount_workshop" / "examples" / "phase_sixteen" / "acceptance_matrix.json"
        matrix = json.loads(matrix_path.read_text(encoding="utf-8"))
        self.assertEqual({item["id"] for item in matrix["workflows"]}, {f"W{i:02d}" for i in range(1, 13)})
        self.assertEqual({item["id"] for item in matrix["scenarios"]}, {f"A{i:02d}" for i in range(1, 13)})
        allowed = {"NOT_RUN", "PASS", "PARTIAL", "FAIL"}
        self.assertIn(matrix["phase16_execution_status"], allowed)
        self.assertTrue(all(item["phase16_execution_status"] in allowed for item in matrix["scenarios"]))
        self.assertTrue(all(item["source_revision"] for item in matrix["scenarios"]))

    def test_final_acceptance_runner_keeps_runtime_claims_explicit(self) -> None:
        source = (ROOT / "scripts" / "final_acceptance.sh").read_text(encoding="utf-8")
        self.assertIn("--static", source)
        self.assertIn("--runtime", source)
        self.assertIn("mix ci", source)
        self.assertIn("FOUNT_PACKAGE_BUILD=1 mix hex.build", source)
        self.assertIn("FOUNT_DATABASE_URL is unset", source)
        self.assertIn("live-provider checks", source)
        self.assertNotIn("curl ", source)


if __name__ == "__main__":
    unittest.main()
