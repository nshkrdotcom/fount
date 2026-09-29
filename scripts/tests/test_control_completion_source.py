"""Phase 05 control/completion source-only contract checks. No Elixir/PostgreSQL execution occurs here."""
import os
import unittest
from pathlib import Path

ROOT = Path(os.environ.get("FOUNT_SOURCE", str(Path(__file__).resolve().parents[2])))


class ControlCompletionSource(unittest.TestCase):
    def read(self, rel):
        return (ROOT / rel).read_text(encoding="utf-8")

    def test_c01_one_canonical_decision_and_approval_surface(self):
        public = self.read("packages/fount_run/lib/fount_run.ex")
        command = self.read("packages/fount_run/lib/fount_run/decision_command.ex")
        self.assertIn("def submit_decision(repo, decision_id, response, actor_context)", public)
        self.assertIn("def approve_run(repo, run_id, response, actor_context)", public)
        self.assertIn("def approve_run(repo, run_id, attrs, %ActorContext{} = context)", command)
        self.assertIn("submit(repo, decision_id, response, context)", command)
        for token in [":stale_decision_context", ":stale_decision_binding", ":decision_conflict"]:
            self.assertIn(token, command + self.read("packages/fount_run/lib/fount_run/persistence.ex"))

    def test_c02_pause_resume_stop_and_terminal_fencing(self):
        public = self.read("packages/fount_run/lib/fount_run.ex")
        control = self.read("packages/fount_run/lib/fount_run/control.ex")
        for token in ["def pause_run(", "def resume_run(", "def stop_run("]:
            self.assertIn(token, public)
        for token in ["pause_requested_at", "stop_requested_at", "fencing_token", "fence_approval_attempts"]:
            self.assertIn(token, control)
        self.assertIn("completed_accepted", control)
        self.assertIn("completed_candidate", control)

    def test_c03_completion_uses_core_and_candidate_delivery_can_remain_headless(self):
        completion = self.read("packages/fount_run/lib/fount_run/completion_handler.ex")
        bridge = self.read("packages/fount_run/lib/fount_run/approval_bridge.ex")
        delivery = self.read("packages/fount_run/lib/fount_run/delivery_bundle.ex")
        self.assertIn("ApprovalBridge", completion)
        self.assertIn("accept_candidate", bridge)
        self.assertIn("candidate", delivery)
        self.assertIn("accepted", delivery)
        self.assertNotIn("use Phoenix", completion + bridge + delivery)

    def test_c04_review_evidence_fallback_and_terminal_non_resurrection(self):
        bridge = self.read("packages/fount_run/lib/fount_run/approval_bridge.ex")
        persistence = self.read("packages/fount_run/lib/fount_run/persistence.ex")
        migration = self.read("packages/fount_run/priv/repo/migrations/20260929010000_control_and_completion.exs")
        for token in ["callback_response", "callback_response_hash", "parent_attempt_id"]:
            self.assertIn(token, persistence + migration)
        for terminal in ["accepted", "rejected", "invalid", "fenced", "failed"]:
            self.assertIn(terminal, persistence)
        self.assertIn("fallback", bridge + self.read("packages/fount_run/lib/fount_run/completion_handler.ex"))

    def test_c05_rebase_and_replacement_require_fresh_candidate_check_bindings(self):
        command = self.read("packages/fount_run/lib/fount_run/decision_command.ex")
        control = self.read("packages/fount_run/lib/fount_run/control.ex")
        self.assertIn("FountWorkshop.Rebase", command)
        self.assertIn("save_edit_candidate", command)
        for token in ["check_set_fingerprint", "plan_version", "policy_version", "candidate_id"]:
            self.assertIn(token, command)
        self.assertIn("successor", control)

    def test_c06_durable_approval_and_delivery_recovery_seams_exist(self):
        bridge = self.read("packages/fount_run/lib/fount_run/approval_bridge.ex")
        delivery = self.read("packages/fount_run/lib/fount_run/delivery_bundle.ex")
        for token in ["approval_callback", "approval_reconciler", "approval_payload", "approval_id"]:
            self.assertIn(token, bridge)
        for token in ["retry_index", "retry_of", "sha256", "pdf", "table_read"]:
            self.assertIn(token, delivery)
        tests = self.read("packages/fount_run/integration/control_completion_test.exs")
        for token in ["after_callback_response_before_persistence", "after_review_persistence", "after_approval_payload_persistence", "after_acceptance_commit"]:
            self.assertIn(token, tests)

    def test_c07_public_api_cli_and_mix_task_are_complete_without_web_host(self):
        public = self.read("packages/fount_run/lib/fount_run.ex")
        cli = self.read("packages/fount_run/lib/fount_run/cli.ex")
        task = self.read("packages/fount_run/lib/mix/tasks/fount.run.ex")
        for command in ["start_run", "get_run", "list_runs", "step", "submit_decision", "update_plan", "update_policy", "pause_run", "resume_run", "stop_run", "approve_run", "deliver"]:
            self.assertIn(f"def {command}", public)
        for command in ["start", "show", "step", "decisions", "decide", "plan", "pause", "resume", "stop", "policy", "approve", "export"]:
            self.assertIn(f'"{command}"', cli)
        self.assertIn("FountRun.CLI", task)
        self.assertFalse((ROOT / "apps" / "fount_web").exists())


if __name__ == "__main__":
    unittest.main()
