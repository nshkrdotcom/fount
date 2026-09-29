"""Phase 03 source-only contract checks. No Elixir/PostgreSQL execution occurs here."""
import os
import unittest
from pathlib import Path

ROOT = Path(os.environ.get("FOUNT_SOURCE", str(Path(__file__).resolve().parents[2])))


class DurableExecutionSource(unittest.TestCase):
    def read(self, rel):
        return (ROOT / rel).read_text(encoding="utf-8")

    def test_w01_real_workshop_handler_and_no_acceptance_path(self):
        handler = self.read("packages/fount_run/lib/fount_run/workshop_handler.ex")
        self.assertIn("Session.open", handler)
        self.assertIn("Session.resume", handler)
        self.assertIn("Store.new(repo, guard: guard)", handler)
        self.assertIn('"changes_canon" => false', handler)
        self.assertNotIn("accept_candidate", handler)
        self.assertNotIn("Review.accept", handler)
        integration = self.read("packages/fount_run/integration/durable_execution_test.exs")
        self.assertIn("W01 real Workshop operation", integration)
        self.assertIn("head.revision.id == root.revision.id", integration)

    def test_w02_provider_intent_reconciliation_and_fault_windows(self):
        store = self.read("packages/fount_run/lib/fount_run/execution_store.ex")
        hook = self.read("packages/fount_run/lib/fount_run/dispatch_hook.ex")
        for token in ["provider_intent", "provider_dispatched", "provider_result", "ambiguous_provider_outcome"]:
            self.assertIn(token, store + hook)
        self.assertIn(":after_provider_call_before_response_persist", hook)
        self.assertIn("status='unknown'", store)
        self.assertIn("reconciliation_state='reserved'", self.read("packages/fount_run/priv/repo/migrations/20260928010000_create_run_foundation.exs"))

    def test_w03_postgres_clock_fencing_heartbeat_and_guard(self):
        store = self.read("packages/fount_run/lib/fount_run/execution_store.ex")
        for token in ["lease_expires_at>now()", "current_fencing_token", "FOR UPDATE", "FOR SHARE OF r,s", "def heartbeat", "def domain_guard"]:
            self.assertIn(token, store)
        self.assertNotIn("System.monotonic_time", store)
        self.assertNotIn("DateTime.utc_now", store)

    def test_w04_atomic_accounting_and_distinct_retry_counters(self):
        store = self.read("packages/fount_run/lib/fount_run/execution_store.ex")
        migration = self.read("packages/fount_run/priv/repo/migrations/20260928020000_durable_execution.exs")
        completion = self.read("packages/fount_workshop/lib/fount_workshop/writing/completion.ex")
        for token in ["malformed_repair_count", "transient_retry_count", "provider_dispatch_count", "measurement_state_count"]:
            self.assertIn(token, store)
            self.assertIn(token, migration)
        self.assertIn("transient_retries", completion)
        self.assertIn("decode_repairs", completion)
        self.assertIn("reserve_usage_locked", store)
        self.assertIn("money_estimate_required", store)

    def test_w05_control_and_safe_progress(self):
        store = self.read("packages/fount_run/lib/fount_run/execution_store.ex")
        self.assertIn("def install_control_request", store)
        self.assertIn("pause_requested_at", store)
        self.assertIn("stop_requested_at", store)
        self.assertIn("provider_request_id,error_category", store)
        progress_select = store.split("def progress", 1)[1].split("def remaining_limits", 1)[0]
        self.assertNotIn("response,", progress_select)
        self.assertNotIn("request_fingerprint", progress_select)

    def test_w06_operation_identity_seams_and_core_independence(self):
        persistence = self.read("packages/fount/lib/fount/persistence.ex")
        migration = self.read("packages/fount/priv/repo/migrations/20260928011000_add_workshop_operation_identity.exs")
        core_mix = self.read("packages/fount/mix.exs")
        for token in ["session_by_operation", "candidate_by_operation", "operation_key", "guarded_write"]:
            self.assertIn(token, persistence)
        self.assertIn("writing_sessions_operation_key_unique", migration)
        self.assertIn("writing_candidates_operation_key_unique", migration)
        self.assertNotIn(":fount_run", core_mix)

    def test_w07_closed_registry_and_explicit_unavailability(self):
        registry = self.read("packages/fount_run/lib/fount_run/stage_registry.ex")
        handler = self.read("packages/fount_run/lib/fount_run/workshop_handler.ex")
        self.assertIn("stage_handler_unavailable", registry)
        self.assertIn("invalid_stage_registry", registry)
        self.assertIn("inference_unavailable", handler)
        self.assertEqual(registry.count('"write" => FountRun.WorkshopHandler'), 1)

    def test_phase03_workshop_handler_remains_write_only_after_later_phases(self):
        public = self.read("packages/fount_run/lib/fount_run.ex")
        handler = self.read("packages/fount_run/lib/fount_run/workshop_handler.ex")
        for token in ["def start_run", "def enqueue_step", "def step(", "def progress("]:
            self.assertIn(token, public)
        self.assertNotIn("investigate", handler)
        self.assertNotIn("accept_candidate", handler)
        self.assertNotIn("Review.accept", handler)

    def test_migrations_are_additive_and_phase02_foundation_remains(self):
        run_migration = self.read("packages/fount_run/priv/repo/migrations/20260928020000_durable_execution.exs")
        core_migration = self.read("packages/fount/priv/repo/migrations/20260928011000_add_workshop_operation_identity.exs")
        self.assertIn("ALTER TABLE fount_run_steps ADD COLUMN", run_migration)
        self.assertIn("CREATE TABLE fount_run_provider_requests", run_migration)
        self.assertNotIn("DROP TABLE fount_run_steps", run_migration)
        self.assertIn("ALTER TABLE writing_sessions ADD COLUMN operation_key", core_migration)
        self.assertIn("ALTER TABLE writing_candidates ADD COLUMN operation_key", core_migration)


if __name__ == "__main__":
    unittest.main()
