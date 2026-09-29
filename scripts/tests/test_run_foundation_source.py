"""Phase 02 Run-foundation source checks. These do not execute Elixir or PostgreSQL."""
import os
import unittest
from pathlib import Path

ROOT = Path(os.environ.get("FOUNT_SOURCE", str(Path(__file__).resolve().parents[2])))
RUN = ROOT / "packages" / "fount_run"


class RunFoundationSource(unittest.TestCase):
    def read(self, rel):
        return (ROOT / rel).read_text(encoding="utf-8")

    def test_five_library_workspace_and_run_package(self):
        packages = {p.name for p in (ROOT / "packages").iterdir() if p.is_dir()}
        self.assertEqual(packages, {"fount", "fount_observe", "fount_intelligence", "fount_workshop", "fount_run"})
        self.assertIn('"packages/fount_run"', self.read("mix.exs"))
        self.assertTrue((RUN / "mix.exs").is_file())
        self.assertTrue((RUN / "mix.lock").is_file())
        self.assertTrue((RUN / "README.md").is_file())

    def test_all_run_tables_and_constraints_are_declared(self):
        migration = self.read("packages/fount_run/priv/repo/migrations/20260928010000_create_run_foundation.exs")
        for table in ["fount_runs", "fount_run_plans", "fount_run_policies", "fount_run_steps", "fount_run_attempts", "fount_run_events", "fount_run_decisions", "fount_run_approval_attempts", "fount_run_usage", "fount_run_deliveries"]:
            self.assertIn(f"CREATE TABLE {table}", migration, table)
        for token in ["fount_run_current_plan_fk", "fount_run_current_policy_fk", "fount_run_active_step_fk", "DEFERRABLE INITIALLY DEFERRED", "fount_run_reject_snapshot_mutation", "fount_run_guard_approval_immutable", "fount_run_guard_decision_identity", "fount_run_guard_usage_reservation", "fount_run_guard_delivery_identity"]:
            self.assertIn(token, migration, token)
        self.assertNotIn("ON DELETE CASCADE", migration)

    def test_execution_boundary_depends_on_workshop_without_direct_provider_or_host_deps(self):
        production = "\n".join(p.read_text(encoding="utf-8") for p in (RUN / "lib").rglob("*.ex"))
        mix = self.read("packages/fount_run/mix.exs")
        self.assertIn("workspace_dep(:fount_workshop", mix)
        for token in [":system_one_sdk", "{:inference", ":agent_session_manager"]:
            self.assertNotIn(token, mix)
        self.assertNotIn("use Ecto.Repo", production)
        self.assertIn("alias FountWorkshop.{Session, Store}", production)
        self.assertIn("Inference.complete", self.read("packages/fount_workshop/lib/fount_workshop/writing/completion.ex"))

    def test_public_surface_adds_only_phase_three_execution_commands(self):
        public = self.read("packages/fount_run/lib/fount_run.ex")
        for command in ["def start_run", "def get_run", "def list_runs", "def enqueue_step", "def step(", "def progress("]:
            self.assertIn(command, public)
        self.assertIn(":telemetry.execute([:fount_run, operation]", public)
        for later in ["def update_plan(", "def pause_run(", "def resume_run(", "def approve_run(", "def deliver("]:
            self.assertNotIn(later, public)
        persistence = self.read("packages/fount_run/lib/fount_run/persistence.ex")
        for primitive in ["append_plan_snapshot", "append_policy_snapshot", "append_event", "put_pending_decision", "resolve_decision", "create_approval_attempt", "record_approval_review", "record_approval_payload", "reserve_usage", "settle_usage", "create_delivery", "store_active_lease"]:
            self.assertIn(f"def {primitive}", persistence, primitive)
        self.assertIn(":acceptance_bridge_required", persistence)

    def test_closed_plan_policy_and_no_arbitrary_atomization(self):
        plan = self.read("packages/fount_run/lib/fount_run/plan.ex")
        policy = self.read("packages/fount_run/lib/fount_run/policy.ex")
        closed = self.read("packages/fount_run/lib/fount_run/closed_map.ex")
        self.assertIn("@operation_keys", plan)
        self.assertIn("max_malformed_repairs_per_call", policy)
        self.assertIn("max_transient_retries", policy)
        self.assertIn("max_inference_calls", policy)
        self.assertIn("max_measurement_states", policy)
        self.assertNotIn("max_repair_rounds", policy)
        self.assertNotIn("String.to_atom(key)", plan + policy)
        self.assertIn("aliases = Map.new(allowed", closed)
        actor_context = self.read("packages/fount_run/lib/fount_run/actor_context.ex")
        self.assertIn("type in [:agent, :service]", actor_context)
        persistence = self.read("packages/fount_run/lib/fount_run/persistence.ex")
        self.assertIn("validate_start_opts", persistence)
        self.assertIn('"principal" => Principal.to_map(context.principal)', persistence)

    def test_core_remains_independent_and_architecture_gate_knows_run(self):
        self.assertNotIn(":fount_run", self.read("packages/fount/mix.exs"))
        architecture = self.read("packages/fount_intelligence/lib/fount/intelligence/runner/architecture.ex")
        self.assertIn("fount_run", architecture)
        self.assertIn('"fount_run" => ["fount", "fount_workshop"]', architecture)
        self.assertIn("FountRun", architecture)
        final = self.read("scripts/final_acceptance.py")
        self.assertIn('"fount_run"', final)
        self.assertIn("exact_five_library_set", final)

    def test_run_integration_and_ci_harness_are_written(self):
        self.assertTrue((RUN / "integration" / "run_foundation_test.exs").is_file())
        integration = self.read("packages/fount_run/integration/run_foundation_test.exs")
        self.assertLess(integration.index("Persistence.migrations_path()"), integration.index("FountRun.migrations_path()"))
        self.assertIn("idempotency_conflict", integration)
        self.assertIn("already_resolved", integration)
        ci = self.read(".github/workflows/ci.yml")
        self.assertIn("working-directory: packages/fount_run", ci)
        self.assertIn("FOUNT_PACKAGE_BUILD=1 mix hex.build", ci)

    def test_snapshot_tooling_includes_new_package_by_glob(self):
        repomix = self.read("repomix.config.json")
        self.assertIn('"packages/**"', repomix)
        self.assertNotIn('"packages/fount_workshop/**"', repomix)

    def test_attempt_storage_primitives(self):
        persistence = self.read("packages/fount_run/lib/fount_run/persistence.ex")
        migration = self.read("packages/fount_run/priv/repo/migrations/20260928010000_create_run_foundation.exs")
        self.assertIn("def begin_attempt", persistence)
        self.assertIn("def finish_attempt", persistence)
        self.assertIn("step_id,attempt_number", persistence)
        self.assertIn("CREATE TABLE fount_run_attempts", migration)
        self.assertIn("fount_run_attempt_terminal_immutable", migration)



if __name__ == "__main__":
    unittest.main()
