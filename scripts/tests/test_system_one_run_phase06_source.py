"""Phase 06 analysis-dashboard and whole-site visual-system source contracts."""
import os
import pathlib
import unittest

ROOT = pathlib.Path(os.environ.get("FOUNT_SOURCE", pathlib.Path(__file__).resolve().parents[2]))


class Phase06AnalysisSourceTest(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_a01_statuses_and_required_advisory_distinction(self):
        dashboard = self.read("apps/fount_web/lib/fount_web/analysis_dashboard.ex")
        live = self.read("apps/fount_web/lib/fount_web/live/analysis_live.ex")
        for state in ("complete", "partial", "failed", "stale", "not_run"):
            self.assertIn(state, dashboard + live)
        self.assertIn("required_deterministic", dashboard)
        self.assertIn("workshop_application", dashboard)
        self.assertIn("semantic_advisory", dashboard)
        self.assertIn("Generation success does not establish analysis completeness", live)

    def test_a02_is_saved_evidence_only_and_owner_scoped(self):
        dashboard = self.read("apps/fount_web/lib/fount_web/analysis_dashboard.ex")
        self.assertIn("FountWeb.Store.run_access", dashboard)
        self.assertIn("FountRun.get_run", dashboard)
        self.assertIn("FountRun.progress", dashboard)
        self.assertIn("FROM analysis_runs", dashboard)
        self.assertIn("FROM analysis_observations", dashboard)
        self.assertIn('id::text = ANY($2::text[])', dashboard)
        self.assertIn('session_id::text = ANY($3::text[])', dashboard)
        self.assertIn('candidate_id::text = ANY($4::text[])', dashboard)
        self.assertIn('legacy_revision', dashboard)
        for forbidden in ("FountWorkshop.", "Fount.Observe.", "Inference.", "reserve_usage", "enqueue_step"):
            self.assertNotIn(forbidden, dashboard)

    def test_a03_review_keeps_exact_candidate_packet_and_check_binding(self):
        run_live = self.read("apps/fount_web/lib/fount_web/live/run_live.ex")
        dashboard = self.read("apps/fount_web/lib/fount_web/analysis_dashboard.ex")
        self.assertIn("Analysis for this revision", run_live)
        for field in ("base_revision_id", "candidate_revision_id", "packet_id", "analysis_run_id", "check_set_fingerprint"):
            self.assertIn(field, run_live + dashboard)
        self.assertIn("Story observations do not replace required checks", run_live)

    def test_a04_graph_is_bounded_interactive_and_accessible(self):
        dashboard = self.read("apps/fount_web/lib/fount_web/analysis_dashboard.ex")
        live = self.read("apps/fount_web/lib/fount_web/live/analysis_live.ex")
        js = self.read("apps/fount_web/assets/js/app.js")
        self.assertIn("@graph_node_limit 48", dashboard)
        self.assertIn("@graph_edge_limit 96", dashboard)
        self.assertIn("story_world_records", dashboard)
        self.assertIn("does not establish cause and effect", dashboard)
        self.assertIn("observation_id", dashboard)
        self.assertIn("evidence_ids", dashboard)
        self.assertIn("Accessible graph list", live)
        self.assertIn("Evidence graph legend", live)
        self.assertIn('phx-hook="AnalysisGraph"', live)
        self.assertIn("pointerdown", js)
        self.assertIn("ArrowLeft", js)

    def test_a05_usage_is_from_durable_ledger_not_measurement_request_guessing(self):
        dashboard = self.read("apps/fount_web/lib/fount_web/analysis_dashboard.ex")
        live = self.read("apps/fount_web/lib/fount_web/live/analysis_live.ex")
        self.assertIn('progress["usage"]', dashboard)
        self.assertIn("outstanding_reserved", dashboard)
        self.assertIn("unknown_rows", dashboard)
        self.assertIn("Measurement states describe recorded work, not HTTP request counts", dashboard)
        self.assertIn('authoritative_resources: progress["resources"]', dashboard)
        self.assertIn("Your configured limits still apply", live)

    def test_a06_comparison_requires_exact_evidence_definitions(self):
        dashboard = self.read("apps/fount_web/lib/fount_web/analysis_dashboard.ex")
        for identity in ("output_contract_sha256", "measurement_identity", "provider_fingerprint", "evidence_identity"):
            self.assertIn(identity, dashboard)
        self.assertIn("analysis scope differs", dashboard)
        self.assertIn("No quality ranking", self.read("apps/fount_web/lib/fount_web/live/analysis_live.ex"))

    def test_a07_evidence_navigation_is_analysis_run_bound(self):
        views = self.read("apps/fount_web/lib/fount_web/screenplay_views.ex")
        editor = self.read("apps/fount_web/lib/fount_web/live/editor_live.ex")
        self.assertIn('"evidence:#{analysis_run_id}:#{revision_id}"', views)
        self.assertIn("WHERE id=$1::text::uuid AND screenplay_id=$2::text::uuid AND revision_id=$3::text::uuid", views)
        self.assertIn("This unsaved draft has not been analyzed", editor)

    def test_whole_site_visual_system_is_dense_and_distinct(self):
        css = self.read("apps/fount_web/assets/css/app.css")
        layout = self.read("apps/fount_web/lib/fount_web/components/layouts/root.html.heex")
        self.assertIn("font-size: 14px; line-height: 1.42", css)
        self.assertNotIn("linear-gradient", css)
        self.assertNotIn(".app-stage::before", css)
        self.assertIn(".system-rail", css)
        self.assertIn(".analysis-layout", css)
        self.assertIn(".authoring-grid", css)
        self.assertIn(".workspace-grid", css)
        self.assertIn(".project-grid", css)
        self.assertIn("@media (max-width: 700px)", css)
        self.assertIn("prefers-reduced-motion", css)
        self.assertIn("Screenplay development", layout)
        self.assertNotIn("evidence-aware", layout)
        self.assertNotIn("durable local host", layout)

    def test_phase06_focused_runtime_suites_are_discoverable_without_overwriting_regressions(self):
        for path in (
            "apps/fount_web/integration/phase06_web_app_test.exs",
            "apps/fount_web/browser/tests/phase06.spec.mjs",
            "apps/fount_web/integration/phase06_analysis_test.exs",
            "apps/fount_web/test/fount_web/phase06_analysis_contract_test.exs",
            "apps/fount_web/browser/tests/phase06_analysis.spec.mjs",
        ):
            self.assertTrue((ROOT / path).is_file(), path)


if __name__ == "__main__":
    unittest.main()
