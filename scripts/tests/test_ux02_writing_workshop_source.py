"""UX02 Writing and workshop source-only contracts.

These checks do not establish Elixir, PostgreSQL, LiveView or browser runtime behavior.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


class UX02WritingWorkshopSourceTest(unittest.TestCase):
    def test_catalog_is_complete_and_routes_through_validated_run_workshop_path(self):
        workflow = read("apps/fount_web/lib/fount_web/workflow_management.ex")
        launch = read("apps/fount_web/lib/fount_web/launch.ex")
        expected = {
            "develop", "rewrite", "pass", "alternatives", "sequence",
            "character", "propagate", "notes", "recover", "investigate",
        }
        enabled = set(re.findall(r'"id" => "([a-z_]+)"[\s\S]{0,220}?"enabled" => true', workflow))
        self.assertEqual(enabled, expected)
        self.assertIn("FountWorkshop.Request.validate", workflow)
        self.assertIn("FountRun.start_run", launch)
        self.assertIn("PipelineRequest.new(request)", launch)
        self.assertNotIn("SystemOneSDK", launch)
        self.assertNotIn("Inference.", launch)

    def test_named_scope_protections_and_provider_free_character_reading_are_bounded(self):
        creative = read("apps/fount_web/lib/fount_web/creative_workspace.ex")
        live = read("apps/fount_web/lib/fount_web/live/project_tools_live.ex")
        self.assertIn("@max_scope 64", creative)
        self.assertIn("@max_protected 32", creative)
        self.assertIn("@max_picker 300", creative)
        self.assertIn("Fount.Selection.selected_ids", creative)
        self.assertIn("Query.character_dialogue", creative)
        self.assertIn("Return to passage", live)
        self.assertIn("Try another line", live)
        self.assertIn("protected_text", creative)

    def test_question_first_brief_uses_progressive_disclosure_not_placeholder_cards(self):
        live = read("apps/fount_web/lib/fount_web/live/project_tools_live.ex")
        js = read("apps/fount_web/assets/js/app.js")
        self.assertIn('id="creative-brief"', live)
        self.assertIn("@primary_workflow_actions", live)
        self.assertIn("All tasks", live)
        self.assertIn("Let the dialogue imply more", live)
        self.assertIn("Look for exposition", live)
        self.assertIn("Explore who has the upper hand", live)
        self.assertIn("data-task-actions", live)
        self.assertIn('name="task[multi_launch]"', live)
        self.assertIn("WorkflowManagement.max_multi_launch()", live)
        self.assertIn('multi? = truthy?(params["multi_launch"])', live)
        self.assertIn('"passages" => selection_passages(model, selection)', read("apps/fount_web/lib/fount_web/workflow_management.ex"))
        self.assertIn("Passage preview", live)
        self.assertIn("const CreativeBrief", js)
        self.assertNotIn("catalog-card", live)

    def test_focus_typewriter_scene_moves_and_recovery_stay_client_safe(self):
        editor = read("apps/fount_web/lib/fount_web/live/editor_live.ex")
        js = read("apps/fount_web/assets/js/app.js")
        self.assertIn("data-authoring-focus", editor)
        self.assertIn("data-authoring-typewriter", editor)
        self.assertIn("prefers-reduced-motion: reduce", js)
        self.assertIn('behavior: "auto"', js)
        self.assertIn('event.key === "Escape"', js)
        self.assertIn('event.altKey && (event.key === "ArrowUp" || event.key === "ArrowDown")', js)
        self.assertIn('this.pushEvent("scene_move"', js)
        self.assertIn("two-tab conflicts and recovery", read("apps/fount_web/lib/fount_web/help.ex"))

    def test_policy_exposes_purposeful_groups_and_exact_currency_conversion(self):
        workflow = read("apps/fount_web/lib/fount_web/workflow_management.ex")
        run_live = read("apps/fount_web/lib/fount_web/live/run_live.ex")
        for label in ["Review steps", "Time and spending limits", "Saved settings", "Technical details"]:
            self.assertIn(label, run_live)
        self.assertIn("max_currency_units", workflow)
        self.assertIn("1_000_000", workflow)
        self.assertIn("max_microunits", workflow)
        self.assertIn("missing cost estimates remain unknown", run_live)
        self.assertIn("Export JSON", run_live)
        self.assertIn('push_event("download-json"', run_live)
        self.assertIn('window.addEventListener("phx:download-json"', read("apps/fount_web/assets/js/app.js"))

    def test_candidate_audition_selection_recombination_and_acceptance_use_existing_contracts(self):
        workspace = read("apps/fount_web/lib/fount_web/candidate_workspace.ex")
        run_live = read("apps/fount_web/lib/fount_web/live/run_live.ex")
        self.assertIn("FountWorkshop.Audition.build", workspace)
        self.assertIn("FountWorkshop.CandidateAPI.select", workspace)
        self.assertIn("FountWorkshop.CandidateAPI.combine", workspace)
        self.assertIn("Audition in context", run_live)
        self.assertIn("Save selected changes as related proposal", run_live)
        self.assertIn("Save recombined proposal", run_live)
        self.assertIn("FountRun.submit_decision", run_live)
        self.assertIn("Save manual adjustment and re-check", run_live)
        self.assertIn("Rebase onto the current screenplay", run_live)

    def test_note_links_are_persisted_owner_source_run_facts_and_recoverable(self):
        migration = read("apps/fount_web/priv/repo/migrations/20261001020000_ux02_writing_workshop.exs")
        tools = read("apps/fount_web/lib/fount_web/production_tools.ex")
        live = read("apps/fount_web/lib/fount_web/live/project_tools_live.ex")
        self.assertIn("fount_web_note_work_links", migration)
        self.assertIn("source_revision_id", migration)
        self.assertIn("source_fingerprint", migration)
        self.assertIn("run_id", migration)
        self.assertIn("project_screenplay_mismatch", tools)
        self.assertIn("run_source_mismatch", tools)
        self.assertIn("source.revision.content_hash", tools)
        self.assertIn("reconcile_note_work_links", tools)
        self.assertIn("Work on this note now", live)
        self.assertIn("Open linked proposal", live)
        self.assertIn("Note-bound task validated", live)
        self.assertIn("This action does not accept screenplay changes", live)

    def test_dependency_versions_and_ux03_boundaries_are_unchanged(self):
        web_mix = read("apps/fount_web/mix.exs")
        workshop_mix = read("packages/fount_workshop/mix.exs")
        observe_mix = read("packages/fount_observe/mix.exs")
        self.assertIn('~> 0.5.1', web_mix)
        self.assertIn('~> 0.5.1', workshop_mix)
        self.assertIn('~> 0.17.3', workshop_mix)
        self.assertIn('~> 0.6.0', observe_mix)
        for body in [web_mix, workshop_mix, observe_mix]:
            self.assertNotRegex(body, r'path:\s*["\'].*(?:system_one_sdk|inference|agent_session_manager)')
        live = read("apps/fount_web/lib/fount_web/live/project_tools_live.ex")
        self.assertIn("A PDF page map is shown only if the renderer actually supplies a verified mapping", live)
        self.assertIn("Microphone capture and automatic performance scoring are not available", live)
        self.assertIn("does not create a Run", live)


if __name__ == "__main__":
    unittest.main()
