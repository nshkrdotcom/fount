import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WEB = ROOT / "apps" / "fount_web"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class Phase07SourceContractTest(unittest.TestCase):
    def test_w01_policy_form_and_presets_are_server_validated(self):
        workflow = read("apps/fount_web/lib/fount_web/workflow_management.ex")
        run_live = read("apps/fount_web/lib/fount_web/live/run_live.ex")
        actors = read("apps/fount_web/lib/fount_web/actors.ex")
        for gate in ["investigation_scope", "strategy_choice", "candidate_generation", "iteration"]:
            self.assertIn(gate, workflow)
            self.assertIn('name={\"policy[#{gate}]\"}', run_live)
        for key in ["max_iterations", "max_inference_calls", "max_measurement_states", "max_microunits"]:
            self.assertIn(key, workflow)
            self.assertIn(key, run_live)
        self.assertIn("Policy.new(value, context)", workflow)
        self.assertIn("resolve_policy_principal", actors)
        self.assertIn("resolve_route_reviewer", actors)
        self.assertIn('"registered_reviewer"', workflow)
        self.assertIn("trusted_owner(context, owner_id)", workflow)
        self.assertIn("save_policy_preset", workflow)

    def test_w02_catalog_is_closed_and_not_a_workshop_module_browser(self):
        workflow = read("apps/fount_web/lib/fount_web/workflow_management.ex")
        enabled = re.findall(r'"id" => "([a-z_]+)",\n\s+"label".*?\n\s+"enabled" => true', workflow)
        self.assertEqual(sorted(enabled), ["develop", "pass", "propagate"])
        for disabled in ["alternatives", "sequence", "character", "notes", "recover", "investigate"]:
            self.assertRegex(workflow, rf'(?s)"id" => "{disabled}".*?"enabled" => false')
        self.assertIn("FountWorkshop.Request.validate", workflow)
        integration = read("apps/fount_web/integration/phase07_workflow_management_test.exs")
        self.assertIn("for action <- ~w(develop pass propagate)", integration)
        self.assertIn("FountRun.step(Fount.Repo, action_run[\"id\"], context, [])", integration)
        self.assertIn("completed_step[\"stage\"] == \"intake\"", integration)
        self.assertNotIn("String.to_existing_atom", workflow)
        self.assertNotIn("Module.concat", workflow)

    def test_w03_scope_uses_fount_selection_and_exact_base(self):
        workflow = read("apps/fount_web/lib/fount_web/workflow_management.ex")
        viewer = read("apps/fount_web/lib/fount_web/live/viewer_live.ex")
        self.assertIn("Fount.Selection.selected_ids", workflow)
        self.assertIn('["plan", "base_revision_id"]', workflow)
        self.assertIn('"kind" => "scene"', workflow)
        self.assertIn('"kind" => "element"', workflow)
        self.assertNotIn('"kind" => "page"', workflow)
        self.assertIn("Saved workflow scope is stale", viewer)

    def test_w04_w05_decision_and_control_bindings_use_run_api(self):
        live = read("apps/fount_web/lib/fount_web/live/run_live.ex")
        for call in ["FountRun.submit_decision", "FountRun.update_plan", "FountRun.update_policy"]:
            self.assertIn(call, live)
        self.assertIn("context_fingerprint", live)
        self.assertIn("check_set_fingerprint", live)
        self.assertIn("analysis_lineage", live)
        self.assertIn('when action in ["pause", "resume"]', live)
        self.assertIn('def handle_event("stop", %{"control" => %{"confirm_stop" => value}}', live)
        self.assertIn("FountRun.stop_run", live)
        workflow = read("apps/fount_web/lib/fount_web/workflow_management.ex")
        self.assertNotIn('analysis = result["analysis"] ||', workflow)
        self.assertIn("exact_review_binding", workflow)
        self.assertIn("restart-from-stage is not supported", workflow)

    def test_w06_exports_remain_existing_delivery_options_and_owner_scoped(self):
        live = read("apps/fount_web/lib/fount_web/live/run_live.ex")
        controller = read("apps/fount_web/lib/fount_web/controllers/artifact_controller.ex")
        self.assertIn("FountRun.deliver", live)
        self.assertIn('pdf: truthy?(selected["pdf"])', live)
        self.assertIn('table_read: truthy?(selected["table_read"])', live)
        self.assertNotIn("docx", live.lower())
        self.assertIn("FountWeb.Store.delivery", controller)
        self.assertIn("checksum(bytes)", controller)
        self.assertIn("@preview_bytes 204_800", controller)
        self.assertIn("table_read_html", controller)

    def test_w07_w08_are_bounded_and_do_not_add_scheduler_or_inbox(self):
        workflow = read("apps/fount_web/lib/fount_web/workflow_management.ex")
        migration = read("apps/fount_web/priv/repo/migrations/20260930120000_phase07_workflow_management.exs")
        events = read("apps/fount_web/lib/fount_web/run_events.ex")
        self.assertIn("@max_multi_launch 8", workflow)
        self.assertIn("@max_run_list 50", workflow)
        store = read("apps/fount_web/lib/fount_web/store.ex")
        self.assertIn("FountWeb.Store.list_run_accesses", workflow)
        self.assertIn("LIMIT $2", store)
        self.assertIn("LIMIT $3", store)
        self.assertNotIn("FountRun.list_runs", workflow)
        self.assertIn("FountWeb.Launch.create_action_from_base", workflow)
        self.assertIn("def notifications(run, progress)", workflow)
        self.assertIn("Phoenix.PubSub", events)
        self.assertNotIn("notification", migration.lower())
        self.assertNotIn("inbox", migration.lower())
        self.assertNotIn("Oban", workflow)

    def test_runtime_runner_requires_phase07_focused_suites(self):
        runner = read("scripts/run_runtime_qc.py")
        self.assertIn("phase07_workflow_management_test.exs", runner)
        self.assertIn("phase07*.spec.mjs", runner.replace("{args.phase:02d}", "07"))
        self.assertIn("scripts/run_phase06_browser.sh", runner)
        self.assertIn("mix", runner)

    def test_hex_dependency_contract_is_unchanged(self):
        web_mix = read("apps/fount_web/mix.exs")
        workshop_mix = read("packages/fount_workshop/mix.exs")
        observe_mix = read("packages/fount_observe/mix.exs")
        self.assertIn('~> 0.5.1', web_mix)
        self.assertIn('~> 0.5.1', workshop_mix)
        self.assertIn('~> 0.17.3', workshop_mix)
        self.assertIn('~> 0.6.0', observe_mix)
        for body in [web_mix, workshop_mix, observe_mix]:
            self.assertNotRegex(body, r'path:\s*["\'].*(?:system_one_sdk|inference|agent_session_manager)')


if __name__ == "__main__":
    unittest.main()
