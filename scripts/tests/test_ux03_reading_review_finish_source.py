"""UX03 Reading, review and finish source-only contracts.

These checks prove the offline overlay's explicit source boundaries only. They do not
establish Elixir/PostgreSQL/LiveView/browser runtime behavior.
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


class UX03ReadingReviewFinishSourceTest(unittest.TestCase):
    def test_migration_keeps_manual_table_reads_run_optional_and_adds_owned_review_facts(self):
        migration = read("apps/fount_web/priv/repo/migrations/20261001030000_ux03_reading_review_finish.exs")
        self.assertIn("ALTER TABLE fount_web_table_reads ALTER COLUMN run_id DROP NOT NULL", migration)
        self.assertIn("fount_web_note_review_responses", migration)
        self.assertIn("reviewed_revision_id", migration)
        self.assertIn("version", migration)
        self.assertIn("fount_web_project_artifacts", migration)
        self.assertIn("source_revision_id", migration)
        self.assertIn("checksum", migration)

    def test_obsolete_task_tools_route_is_not_current_experience(self):
        router = read("apps/fount_web/lib/fount_web/router.ex")
        self.assertNotIn('live "/p/:key/tools/:task_key"', router)
        for path in [
            'live "/p/:key/notes"',
            'live "/p/:key/cast"',
            'live "/p/:key/read"',
            'live "/p/:key/feedback"',
            'live "/p/:key/exports"',
        ]:
            self.assertIn(path, router)

    def test_reading_search_and_comparison_are_source_bound(self):
        viewer = read("apps/fount_web/lib/fount_web/live/viewer_live.ex")
        comparison = read("apps/fount_web/lib/fount_web/components/source_comparison.ex")
        tools = read("apps/fount_web/lib/fount_web/production_tools.ex")
        self.assertIn('phx-submit="search_script"', viewer)
        self.assertIn("Exact literal search", viewer)
        self.assertIn("ProductionTools.search", viewer)
        self.assertIn("SourceComparison", viewer)
        self.assertIn("Current", comparison)
        self.assertIn("compare-proposed", comparison)
        self.assertIn("proposed", comparison)
        self.assertIn("Changes", comparison)
        self.assertIn("Search.find", tools)
        self.assertNotIn("Inference.", tools)

    def test_notes_cast_table_read_feedback_and_exports_preserve_authority(self):
        live = read("apps/fount_web/lib/fount_web/live/project_tools_live.ex")
        for phrase in [
            "Build notes memo",
            "Save reviewer response",
            "This action does not accept screenplay changes",
            "Prepare name change",
            "Cast & locations",
            "does not create a Run",
            "Microphone capture and automatic performance scoring are not available",
            "Was this useful?",
            "I kept my original",
            "Every optional dimension remains independent",
            "Build Fountain",
            "Build FDX",
            "Build PDF",
        ]:
            self.assertIn(phrase, live)

    def test_table_read_client_controls_are_finite_and_reduced_motion_safe(self):
        js = read("apps/fount_web/assets/js/app.js")
        self.assertIn("TableReadWorkspace", js)
        self.assertIn("Math.max(.5, Math.min(2", js)
        self.assertIn("prefers-reduced-motion: reduce", js)
        self.assertIn("ArrowDown", js)
        self.assertIn("ArrowUp", js)
        self.assertIn("PageDown", js)
        self.assertIn("table_read_state", js)

    def test_project_artifacts_use_existing_renderers_and_owner_binding(self):
        artifacts = read("apps/fount_web/lib/fount_web/reading_artifacts.ex")
        controller = read("apps/fount_web/lib/fount_web/controllers/project_artifact_controller.ex")
        self.assertIn("Fount.Screenplay.export_fountain", artifacts)
        self.assertIn("Fount.Screenplay.to_fdx", artifacts)
        self.assertIn("FountWorkshop.Export.PDF.export", artifacts)
        self.assertIn('"page_map" => "unavailable"', artifacts)
        self.assertIn("project_artifact_by_ref", controller)
        self.assertIn("current_owner", controller)


    def test_selected_passage_notes_and_comparison_navigation_are_wired(self):
        viewer = read("apps/fount_web/lib/fount_web/live/viewer_live.ex")
        js = read("apps/fount_web/assets/js/app.js")
        comparison = read("apps/fount_web/lib/fount_web/components/source_comparison.ex")
        self.assertIn('phx-hook="PassageNote"', viewer)
        self.assertIn('data-source-revision=', viewer)
        self.assertIn("source_revision", js)
        self.assertIn("PassageNote", js)
        self.assertIn('phx-hook="SourceComparison"', comparison)
        self.assertIn("data-compare-prev", comparison)
        self.assertIn("data-compare-next", comparison)
        self.assertIn("SourceComparison", js)

    def test_note_review_filters_conflicts_and_open_semantics_are_explicit(self):
        live = read("apps/fount_web/lib/fount_web/live/project_tools_live.ex")
        store = read("apps/fount_web/lib/fount_web/production_store.ex")
        tools = read("apps/fount_web/lib/fount_web/production_tools.ex")
        self.assertIn('name="notes[category]"', live)
        self.assertIn('name="notes[status]"', live)
        self.assertIn("Remap to a named search result", live)
        self.assertIn("Your attempted response is preserved", live)
        self.assertIn("Open means no reviewer-response record", live)
        self.assertIn("clear_note_review", store)
        self.assertIn("ProductionStore.clear_note_review", tools)

    def test_feedback_table_read_print_and_submission_finish_loops_are_present(self):
        live = read("apps/fount_web/lib/fount_web/live/project_tools_live.ex")
        tools = read("apps/fount_web/lib/fount_web/production_tools.ex")
        store = read("apps/fount_web/lib/fount_web/production_store.ex")
        css = read("apps/fount_web/assets/css/app.css")
        self.assertIn("display_title", tools)
        self.assertIn("save_usefulness", tools)
        self.assertIn("update_usefulness", store)
        self.assertIn("reviewable_runs", live)
        self.assertIn("Check current PDF", live)
        self.assertIn("FountWorkshop.Submission.check", live)
        self.assertIn("Recorded rule source", live)
        self.assertIn("@media print", css)

    def test_stale_source_fallback_reloads_current_instead_of_only_relabeling(self):
        viewer = read("apps/fount_web/lib/fount_web/live/viewer_live.ex")
        self.assertIn('current_source = ProjectContext.source_token("current")', viewer)
        self.assertIn('source: current_source', viewer)
        self.assertIn("That saved source is no longer available. Showing the current screenplay.", viewer)

    def test_help_and_dependency_boundaries_are_complete(self):
        help = read("apps/fount_web/lib/fount_web/help.ex")
        for topic in ["script-search", "cast-locations", "analysis", "table-read", "feedback", "exports"]:
            self.assertIn(topic, help)
        web_mix = read("apps/fount_web/mix.exs")
        workshop_mix = read("packages/fount_workshop/mix.exs")
        observe_mix = read("packages/fount_observe/mix.exs")
        self.assertIn('~> 0.5.1', web_mix)
        self.assertIn('~> 0.5.1', workshop_mix)
        self.assertIn('~> 0.17.3', workshop_mix)
        self.assertIn('~> 0.6.0', observe_mix)
        self.assertNotIn("SystemOneSDK", read("apps/fount_web/lib/fount_web/reading_artifacts.ex"))


if __name__ == "__main__":
    unittest.main()
