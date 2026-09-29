"""Phase 04 screenplay-pipeline source checks. Runtime acceptance remains local-QC only."""
import os
import unittest
from pathlib import Path

ROOT = Path(os.environ.get("FOUNT_SOURCE", str(Path(__file__).resolve().parents[2])))


class ScreenplayPipelineSource(unittest.TestCase):
    def read(self, rel):
        return (ROOT / rel).read_text(encoding="utf-8")

    def test_p01_headless_journey_is_real_and_stops_before_canon(self):
        registry = self.read("packages/fount_run/lib/fount_run/stage_registry.ex")
        pipeline = self.read("packages/fount_run/lib/fount_run/pipeline_handler.ex")
        write = self.read("packages/fount_run/lib/fount_run/workshop_handler.ex")
        for stage in ["intake", "investigate", "plan", "check", "iterate"]:
            self.assertIn(f'"{stage}" => FountRun.PipelineHandler', registry)
        self.assertIn('"write" => FountRun.WorkshopHandler', registry)
        self.assertIn("Session.preflight", pipeline)
        self.assertIn("Session.prepare_only", pipeline)
        self.assertIn("Session.plan_only", pipeline)
        self.assertIn("Strategy.materialize", write)
        self.assertIn('"changes_canon" => false', pipeline + write)
        self.assertNotIn("Persistence.accept", pipeline + write)

    def test_p02_investigation_routes_reports_and_uncertainty_are_persisted(self):
        pipeline = self.read("packages/fount_run/lib/fount_run/pipeline_handler.ex")
        for token in ['"workflow" => "investigate"', '"write_fixes" => false', '"uncertainty"', '"report_ids"', '"strategies" => strategies']:
            self.assertIn(token, pipeline)
        request = self.read("packages/fount_workshop/lib/fount_workshop/request.ex")
        for workflow in ["develop", "alternatives", "propagate", "sequence", "character", "notes", "pass", "recover", "investigate"]:
            self.assertIn(f'"{workflow}"', request)

    def test_p03_strategy_submission_is_exact_atomic_and_replay_safe(self):
        public = self.read("packages/fount_run/lib/fount_run.ex")
        persistence = self.read("packages/fount_run/lib/fount_run/persistence.ex")
        pipeline = self.read("packages/fount_run/lib/fount_run/pipeline_handler.ex")
        self.assertIn("def submit_decision(repo, decision_id, response, actor_context)", public)
        self.assertIn("def submit_strategy_decision", persistence)
        self.assertIn("~w(choice context_fingerprint plan_version policy_version)", persistence)
        for token in [":stale_decision_context", ":stale_decision_binding", ":stale_decision", ":decision_conflict", ":unknown_decision_choice", '"replay" => replay']:
            self.assertIn(token, persistence)
        self.assertIn("transaction(repo, fn -> do_submit_strategy_decision", persistence)
        self.assertIn(":pages_generated_before_strategy_decision", pipeline)
        self.assertLess(pipeline.index("Session.plan_only"), pipeline.index(":pages_generated_before_strategy_decision"))

    def test_p04_iteration_is_durable_capped_and_has_no_hidden_repair_loop(self):
        pipeline = self.read("packages/fount_run/lib/fount_run/pipeline_handler.ex")
        write = self.read("packages/fount_run/lib/fount_run/workshop_handler.ex")
        execution = self.read("packages/fount_run/lib/fount_run/execution_store.ex")
        self.assertIn('"stage" => stage', pipeline)
        self.assertIn('schedule(repo, claim, "iterate"', pipeline)
        self.assertIn(":iteration_limit_reached", pipeline)
        self.assertIn('"max_iterations"', pipeline)
        self.assertIn("max_repair_rounds: 0", pipeline + write)
        for counter in ["malformed_repair_count", "transient_retry_count", "provider_dispatch_count", "measurement_state_count"]:
            self.assertIn(counter, execution)

    def test_p05_candidates_remain_on_canonical_base_with_lineage_and_required_checks(self):
        pipeline = self.read("packages/fount_run/lib/fount_run/pipeline_handler.ex")
        self.assertIn(":candidate_base_mismatch", pipeline)
        self.assertIn('"parent_candidate_id"', pipeline)
        self.assertIn('"kind" => "scope"', pipeline)
        self.assertIn('"kind" => "protected_material"', pipeline)
        self.assertIn('"severity" => "required"', pipeline)
        self.assertIn('"lineage"', pipeline)
        self.assertIn('"report_ids"', pipeline)
        self.assertNotIn("accept_candidate", pipeline)

    def test_p06_progress_resume_and_phase03_idempotency_remain_visible(self):
        progress = self.read("packages/fount_run/lib/fount_run/execution_store.ex")
        pipeline = self.read("packages/fount_run/lib/fount_run/pipeline_handler.ex")
        persistence = self.read("packages/fount_run/lib/fount_run/persistence.ex")
        self.assertIn('"decisions" => decisions', progress)
        self.assertIn('claim["operation_key"] <> ":next:" <> stage', pipeline)
        self.assertIn("do_create_step", persistence)
        self.assertIn("decision_replay_missing_step", persistence)
        self.assertIn("provider_requests", progress)
        self.assertIn("ambiguous_provider?", progress)

    def test_p07_later_acceptance_delivery_remain_unimplemented(self):
        registry = self.read("packages/fount_run/lib/fount_run/stage_registry.ex")
        public = self.read("packages/fount_run/lib/fount_run.ex")
        self.assertNotIn('"decide" =>', registry)
        self.assertNotIn('"deliver" =>', registry)
        for later in ["def approve_run(", "def accept(", "def deliver("]:
            self.assertNotIn(later, public)
        durable = self.read("packages/fount_run/integration/durable_execution_test.exs")
        self.assertIn('stage_handler_unavailable, "deliver"', durable)


if __name__ == "__main__":
    unittest.main()
