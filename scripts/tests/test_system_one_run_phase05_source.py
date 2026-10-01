"""Phase 05 interactive-authoring source-only contract checks."""
import os
import pathlib
import unittest

ROOT = pathlib.Path(os.environ.get("FOUNT_SOURCE", pathlib.Path(__file__).resolve().parents[2]))


class Phase05AuthoringSourceTest(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_e01_reconciler_preserves_existing_identity_contract(self):
        source = self.read("packages/fount/lib/fount/screenplay/source_reconciler.ex")
        tests = self.read("packages/fount/test/fount/screenplay/source_reconciler_test.exs")
        self.assertIn("Fount.reparse(prior, raw", source)
        self.assertIn("Identity.anchors(base.ir)", source)
        self.assertIn('"exact_source_round_trip"', source)
        self.assertIn('"preserved_element_ids"', source)
        self.assertIn('"preserved_cast_ids"', source)
        self.assertIn("preserves unaffected identities", tests)
        self.assertIn("raw input", tests)

    def test_e02_e03_debounced_preview_and_bounded_histories(self):
        js = self.read("apps/fount_web/assets/js/app.js")
        live = self.read("apps/fount_web/lib/fount_web/live/editor_live.ex")
        self.assertIn("setTimeout(() => this.preview(), 300)", js)
        self.assertIn("this.maxHistory = 100", js)
        self.assertIn("compositionstart", js)
        self.assertIn("replace_source_rejected", js)
        self.assertIn("@structural_history_limit 50", live)
        self.assertIn("Fount.Screenplay.undo(current, prior)", live)
        self.assertIn("Fount.Screenplay.redo(current, subsequent)", live)
        self.assertIn("last valid draft", live.lower())

    def test_e04_supported_structural_surface_uses_existing_ops_only(self):
        live = self.read("apps/fount_web/lib/fount_web/live/editor_live.ex")
        for operation in (
            "Fount.Edit.replace_text",
            "Fount.Edit.set_character_cue",
            "Fount.Edit.insert_scene_after",
            '"kind" => "insert_elements"',
            '"kind" => "delete_elements"',
            "Fount.Edit.delete_scene",
            "Fount.Edit.move_scene",
        ):
            self.assertIn(operation, live)
        self.assertIn("Generic element move/split/merge is intentionally not offered", live)
        self.assertNotIn("split_element", live)
        self.assertNotIn("merge_element", live)

    def test_e05_durable_drafts_are_owner_scoped_versioned_and_candidate_only(self):
        store = self.read("apps/fount_web/lib/fount_web/authoring_store.ex")
        migration = self.read("apps/fount_web/priv/repo/migrations/20260930053000_create_fount_web_authoring_tables.exs")
        authoring = self.read("apps/fount_web/lib/fount_web/authoring.ex")
        self.assertIn("owner_id=$1", store)
        self.assertIn("version=version+1", store)
        self.assertIn("{:stale_draft, public_conflict(draft)}", store)
        self.assertIn("def fork", store)
        self.assertIn("def restore", store)
        self.assertIn("history_limit", self.read("apps/fount_web/config/config.exs"))
        self.assertIn("fount_web_drafts", migration)
        self.assertIn("Fount.Persistence.save_edit_candidate", authoring)
        self.assertIn("Fount.Persistence.accept_candidate", authoring)
        self.assertNotIn("Fount.Persistence.save(Fount.Repo", authoring)

    def test_e06_ai_uses_existing_run_path_and_exact_saved_candidate(self):
        authoring = self.read("apps/fount_web/lib/fount_web/authoring.ex")
        launch = self.read("apps/fount_web/lib/fount_web/launch.ex")
        self.assertIn("FountWeb.Launch.create_from_candidate", authoring)
        self.assertIn("FountWeb.WorkerSupervisor.start_run", authoring)
        self.assertIn("FountRun.start_run", launch)
        self.assertIn("FountRun.enqueue_step", launch)
        self.assertIn('candidate["base_revision_id"] == head.revision.id', launch)
        self.assertNotIn("FountWorkshop.pass", authoring)
        self.assertNotIn("Inference.", authoring)

    def test_e07_no_shared_body_cache_and_browser_cases_exist(self):
        js = self.read("apps/fount_web/assets/js/app.js")
        browser = self.read("apps/fount_web/browser/tests/phase05_authoring.spec.mjs")
        self.assertNotIn("localStorage", js)
        self.assertIn("fount:passage:", js)
        self.assertEqual(js.count("sessionStorage."), 2)
        self.assertIn("beforeunload", js)
        self.assertIn("Unicode", browser)
        self.assertIn("CompositionEvent", browser)
        self.assertIn("two tabs", browser)
        self.assertIn("480", browser)

    def test_phase05_focused_runtime_suites_are_discoverable(self):
        self.assertTrue((ROOT / "apps/fount_web/integration/phase05_authoring_test.exs").is_file())
        self.assertTrue((ROOT / "apps/fount_web/test/fount_web/phase05_authoring_contract_test.exs").is_file())
        self.assertTrue((ROOT / "apps/fount_web/browser/tests/phase05_authoring.spec.mjs").is_file())


if __name__ == "__main__":
    unittest.main()
