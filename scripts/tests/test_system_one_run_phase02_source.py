"""Phase 02 System One Run reintegration source checks.

These checks intentionally avoid Elixir/PostgreSQL execution. Runtime acceptance belongs to
PHASE_02_RUNTIME_QC_HANDOFF.md.
"""
import os
import unittest
from pathlib import Path

ROOT = Path(os.environ.get("FOUNT_SOURCE", str(Path(__file__).resolve().parents[2])))


class SystemOneRunPhase02Source(unittest.TestCase):
    def read(self, rel):
        return (ROOT / rel).read_text(encoding="utf-8")

    def test_d01_uses_existing_run_measurement_accounting(self):
        execution = self.read("packages/fount_run/lib/fount_run/execution_store.ex")
        pipeline = self.read("packages/fount_run/lib/fount_run/pipeline_handler.ex")
        workshop = self.read("packages/fount_run/lib/fount_run/workshop_handler.ex")
        for token in [
            "def reserve_measurement",
            '"measurement_states"',
            "consumed_quantity(repo, run[\"id\"], \"measurement_states\")",
            '"exhausted" => consumed >= limit',
        ]:
            self.assertIn(token, execution)
        self.assertIn("reservation_hook: reservation_hook", pipeline)
        self.assertIn("reservation_hook: reservation_hook", workshop)

    def test_d02_d03_d04_surface_safe_persisted_analysis_identity(self):
        lineage = self.read("packages/fount_run/lib/fount_run/analysis_lineage.ex")
        execution = self.read("packages/fount_run/lib/fount_run/execution_store.ex")
        integration = self.read("packages/fount_run/integration/screenplay_pipeline_test.exs")
        for token in [
            '"packet_id"',
            '"analysis_run_id"',
            '"status"',
            '"cache_hits"',
            '"scheduled_states"',
        ]:
            self.assertIn(token, lineage)
        self.assertIn('"analysis" => AnalysisLineage.progress(steps)', execution)
        self.assertIn('"resources" => resources', execution)
        self.assertIn("analysis_measurement_results", integration)
        self.assertIn("access_count", integration)
        self.assertIn("d03-changed", integration)

    def test_d05_has_only_the_needed_preanalysis_fault_seam_and_candidate_recovery_seam(self):
        pipeline = self.read("packages/fount_run/lib/fount_run/pipeline_handler.ex")
        workshop = self.read("packages/fount_run/lib/fount_run/workshop_handler.ex")
        integration = self.read("packages/fount_run/integration/screenplay_pipeline_test.exs")
        self.assertIn(":after_pre_analysis_persisted", pipeline)
        self.assertIn(":after_candidate_persisted", workshop)
        self.assertIn("phase02_pre_analysis_crash", integration)
        self.assertIn("phase02_candidate_crash", integration)
        self.assertIn("phase02-fence-policy", integration)
        self.assertIn("expire_active_lease", integration)

    def test_d06_check_is_store_only_and_reuses_candidate_analysis(self):
        pipeline = self.read("packages/fount_run/lib/fount_run/pipeline_handler.ex")
        start = pipeline.index("  defp check(claim, envelope, opts) do")
        end = pipeline.index("  defp check_outcome", start)
        check = pipeline[start:end]
        self.assertIn("services = %{store: Store.new(repo)}", check)
        self.assertNotIn("Session.", check)
        self.assertNotIn("observe", check)
        self.assertIn('"analysis" => AnalysisLineage.from_candidate(candidate)', pipeline)
        self.assertIn('"severity" => "required"', pipeline)

    def test_d07_iterate_is_capped_parented_reanalysed_and_schedules_one_check_key(self):
        pipeline = self.read("packages/fount_run/lib/fount_run/pipeline_handler.ex")
        start = pipeline.index("  defp iterate(claim, envelope, opts) do")
        end = pipeline.index("  defp schedule(", start)
        iterate = pipeline[start:end]
        self.assertIn("check_iteration_limit", iterate)
        self.assertIn('"parent_candidate_id"', iterate)
        self.assertIn("workshop_opts(repo, claim", iterate)
        self.assertIn('schedule(repo, claim, "check"', iterate)
        self.assertIn('"analysis" => AnalysisLineage.from_candidates(candidates)', iterate)
        self.assertIn('claim["operation_key"] <> ":next:" <> stage', pipeline)

    def test_run_keeps_system_one_sdk_types_below_observe(self):
        mix = self.read("packages/fount_run/mix.exs")
        production = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (ROOT / "packages" / "fount_run" / "lib").rglob("*.ex")
        )
        self.assertNotIn(":system_one_sdk", mix)
        self.assertNotIn("SystemOneSDK", production)
        self.assertNotIn(":system_one_sdk", production)


if __name__ == "__main__":
    unittest.main()
