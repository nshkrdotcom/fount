import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class Phase04UISourceTest(unittest.TestCase):
    def text(self, relative):
        return (ROOT / relative).read_text()

    def test_u01_u03_components_and_pure_renderer_exist(self):
        core = self.text("apps/fount_web/lib/fount_web/components/core_components.ex")
        renderer = self.text("apps/fount_web/lib/fount_web/components/screenplay_renderer.ex")
        for name in ("button", "input", "select", "card", "status_badge", "alert", "loading_state", "empty_state", "error_state", "dialog"):
            self.assertIn(f"def {name}", core)
        self.assertIn('phx-hook="AccessibleDialog"', core)
        self.assertIn("screenplay-element--fallback", renderer)
        self.assertIn("screenplay-dual", renderer)
        self.assertNotIn("Inference", renderer)
        self.assertNotIn("Fount.Observe", renderer)

    def test_u04_u05_indices_are_server_linked_analyzer_projections(self):
        live = self.text("apps/fount_web/lib/fount_web/live/viewer_live.ex")
        index = self.text("apps/fount_web/lib/fount_web/screenplay_index.ex")
        self.assertIn('href={"#scene-#{scene.id}"}', live)
        self.assertIn("data-scene-link", live)
        self.assertIn("Fount.Analyzers", index)
        self.assertIn("derived reading approximation", index)
        self.assertNotIn("Inference", index)
        self.assertNotIn("Fount.Observe", index)

    def test_u06_u08_preserve_diff_and_run_identity_boundaries(self):
        views = self.text("apps/fount_web/lib/fount_web/screenplay_views.ex")
        diff = self.text("apps/fount_web/lib/fount_web/components/diff_viewer.ex")
        router = self.text("apps/fount_web/lib/fount_web/router.ex")
        run_live = self.text("apps/fount_web/lib/fount_web/live/run_live.ex")
        self.assertIn("Fount.Screenplay.diff", diff)
        self.assertNotIn("Fount.Diff", diff)
        self.assertIn("Persistence.load_revision", views)
        self.assertIn("Persistence.candidate", views)
        self.assertIn("run_id=$2::text::uuid", views)
        self.assertIn('live "/runs/:id/viewer", ViewerLive, :show', router)
        self.assertIn("FountWeb.Components.DiffViewer.diff", run_live)

    def test_u07_hooks_cleanup_and_scope_shortcuts(self):
        js = self.text("apps/fount_web/assets/js/app.js")
        self.assertIn("SceneNavigator", js)
        self.assertIn("AccessibleDialog", js)
        self.assertGreaterEqual(js.count("removeEventListener"), 4)
        self.assertIn("contenteditable", js)
        self.assertIn("prefers-reduced-motion: reduce", js)

    def test_plain_css_tokens_and_no_tailwind_migration(self):
        css = self.text("apps/fount_web/assets/css/app.css")
        self.assertIn(":root", css)
        self.assertIn("--font-screenplay", css)
        self.assertIn("prefers-color-scheme: dark", css)
        self.assertIn("prefers-reduced-motion: reduce", css)
        self.assertIn("workspace-grid", css)
        self.assertNotIn("@tailwind", css)


if __name__ == "__main__":
    unittest.main()
