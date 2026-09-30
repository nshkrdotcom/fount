"""Phase 03 System One Run host-integration source checks.

These checks are source/static only. Elixir, PostgreSQL, browser, package-build and provider
runtime certification remains the responsibility of PHASE_03_RUNTIME_QC_HANDOFF.md.
"""
import os
import unittest
from pathlib import Path

ROOT = Path(os.environ.get("FOUNT_SOURCE", str(Path(__file__).resolve().parents[2])))


class SystemOneRunPhase03Source(unittest.TestCase):
    def read(self, rel):
        return (ROOT / rel).read_text(encoding="utf-8")

    def test_h01_host_constructs_observe_through_public_boundary(self):
        services = self.read("apps/fount_web/lib/fount_web/services.ex")
        mix = self.read("apps/fount_web/mix.exs")
        self.assertIn("Fount.Observe.provider(provider_opts)", services)
        self.assertIn("alias Fount.Observe.Sandbox", services)
        self.assertIn('"objective" => 0.9', services)
        self.assertIn('"intended_effect_present" => 0.9', services)
        self.assertIn("def observe_provider(screenplay_id, run)", services)
        self.assertIn("Keyword.put(opts, :observe, observe)", services)
        self.assertIn('{:fount_observe, path: "../../packages/fount_observe"}', mix)
        self.assertNotIn("SystemOneSDK", services)

    def test_h02_runtime_modes_are_explicit_and_fail_closed(self):
        runtime = self.read("apps/fount_web/config/runtime.exs")
        for token in [
            '"FOUNT_OBSERVE_MODE"',
            '"FOUNT_SYSTEM_ONE_ENDPOINT_KIND"',
            '"SYSTEM_ONE_API_KEY"',
            '"SYSTEM_ONE_BASE_URL"',
            '"SYSTEM_ONE_MODEL"',
            '"compatibility"',
            '"system_one"',
            '"sandbox"',
        ]:
            self.assertIn(token, runtime)
        self.assertIn("is not allowed in production", runtime)
        self.assertIn("must not contain URL credentials", runtime)

    def test_h03_h05_demo_exercises_prewrite_revision_and_reconnect(self):
        journeys = self.read("apps/fount_web/lib/fount_web/journeys.ex")
        project_live = self.read("apps/fount_web/lib/fount_web/live/project_live.ex")
        integration = self.read("apps/fount_web/integration/phase06_web_app_test.exs")
        browser = self.read("apps/fount_web/browser/tests/phase06.spec.mjs")
        self.assertIn("JOURNEY:analysis", journeys)
        self.assertIn('"completion" => completion', journeys)
        self.assertIn('<option value="analysis">', project_live)
        self.assertIn("H01-H05 deterministic host journey", integration)
        self.assertIn('prewrite["analysis_run_id"]', integration)
        self.assertIn('revision["analysis_run_id"]', integration)
        self.assertIn('canonical.revision.id == run["plan"]["base_revision_id"]', integration)
        self.assertIn("integrated analysis survives review reconnect", browser)
        self.assertIn("Semantic advisory checks", browser)
        self.assertIn("Authoritative required checks", browser)

    def test_h04_ui_uses_safe_lineage_and_separates_check_layers(self):
        live = self.read("apps/fount_web/lib/fount_web/live/run_live.ex")
        self.assertIn('progress["analysis"]', live)
        self.assertIn("Prewrite Intelligence", live)
        self.assertIn("Revision Intelligence", live)
        self.assertIn("Semantic advisory checks", live)
        self.assertIn("Authoritative required checks", live)
        self.assertIn('&(&1["severity"] == "advisory")', live)
        self.assertIn('&(&1["severity"] == "required")', live)
        self.assertIn('defp analysis_status(%{"status" => "not_run"}), do: "not-run"', live)
        self.assertIn('"status" => "failed"', live)

    def test_h06_package_boundaries_remain_intact(self):
        run_mix = self.read("packages/fount_run/mix.exs")
        run_source = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (ROOT / "packages" / "fount_run" / "lib").rglob("*.ex")
        )
        self.assertNotIn(":system_one_sdk", run_mix)
        self.assertNotIn("SystemOneSDK", run_source)
        host_native_refs = [
            path.relative_to(ROOT).as_posix()
            for search_root in (
                ROOT / "apps" / "fount_web" / "lib",
                ROOT / "apps" / "fount_web" / "config",
            )
            for path in search_root.rglob("*.ex*")
            if "SystemOneSDK" in path.read_text(encoding="utf-8")
        ]
        self.assertEqual(host_native_refs, [])
        native_refs = []
        for path in (ROOT / "packages").glob("*/lib/**/*.ex"):
            if "SystemOneSDK" in path.read_text(encoding="utf-8"):
                rel = path.relative_to(ROOT).as_posix()
                if rel != "packages/fount_intelligence/lib/fount/intelligence/runner/architecture.ex":
                    native_refs.append(rel)
        self.assertEqual(
            native_refs,
            ["packages/fount_observe/lib/fount/observe/providers/system_one.ex"],
        )


if __name__ == "__main__":
    unittest.main()
