from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("phase06_acceptance", ROOT / "scripts" / "phase06_acceptance.py")
assert SPEC and SPEC.loader
phase06 = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(phase06)


class Phase06WebSourceTests(unittest.TestCase):
    def test_phase06_source_audit_passes(self) -> None:
        report = phase06.audit()
        failures = [item for item in report["checks"] if item["status"] != "pass"]
        self.assertEqual(failures, [], failures)
        self.assertEqual(report["status"], "pass")
        self.assertTrue(all(value == "NOT_RUN" for value in report["runtime"].values()))

    def test_host_is_not_a_sixth_library(self) -> None:
        self.assertTrue((ROOT / "apps" / "fount_web" / "mix.exs").is_file())
        self.assertFalse((ROOT / "packages" / "fount_web").exists())

    def test_readme_records_resolved_locks_and_pdf_quality_limits(self) -> None:
        readme = (ROOT / "apps" / "fount_web" / "README.md").read_text(encoding="utf-8")
        self.assertIn("locks were resolved during Phase 06 runtime QC", readme)
        self.assertTrue((ROOT / "apps" / "fount_web" / "mix.lock").is_file())
        self.assertTrue((ROOT / "apps" / "fount_web" / "browser" / "package-lock.json").is_file())
        self.assertIn("PDF is never faked", readme)
        self.assertIn("does not certify screenplay quality", readme)


if __name__ == "__main__":
    unittest.main()
