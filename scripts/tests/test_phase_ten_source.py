from __future__ import annotations

import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class PhaseTenSourceTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_durable_analysis_surface_is_present_without_new_package(self) -> None:
        required = [
            "packages/fount/priv/repo/migrations/20260927000000_create_durable_analysis_state.exs",
            "packages/fount/lib/fount/persistence/analysis.ex",
            "packages/fount_intelligence/lib/fount/intelligence/persistence.ex",
            "packages/fount_intelligence/lib/fount/intelligence/persistence/measurement_cache.ex",
            "packages/fount_intelligence/lib/fount/intelligence/recomputation.ex",
            "packages/fount_intelligence/guides/durable-analysis.md",
            "packages/fount_intelligence/integration/phase_ten_durable_analysis_test.exs",
            "packages/fount_workshop/integration/phase_ten_resume_history_test.exs",
        ]
        for path in required:
            self.assertTrue((ROOT / path).is_file(), path)
        self.assertFalse((ROOT / "packages" / "fount_analysis").exists())

    def test_cache_identity_is_privacy_namespaced_and_measurements_are_separate_from_observations(self) -> None:
        migration = self.read(
            "packages/fount/priv/repo/migrations/20260927000000_create_durable_analysis_state.exs"
        )
        self.assertIn("PRIMARY KEY (privacy_namespace,cache_key,ordinal)", migration)
        self.assertIn("analysis_measurement_results", migration)
        self.assertIn("analysis_observations", migration)
        self.assertIn("output_contract_sha256", migration)
        self.assertIn("revision_content_sha256", migration)
        self.assertNotIn("FOREIGN KEY (screenplay_id,revision_id) REFERENCES revisions", migration)
        self.assertNotIn("domain_version", migration)
        self.assertNotIn("schema_version", migration)

    def test_existing_observe_cache_and_model_stability_contracts_are_used(self) -> None:
        adapter = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/persistence/measurement_cache.ex"
        )
        shell = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/persistence.ex"
        )
        observe = self.read("packages/fount_observe/lib/fount/observe/fingerprint.ex")
        self.assertIn("@behaviour Fount.Observe.Cache", adapter)
        self.assertIn("cache_policy, :durable", shell)
        self.assertIn("unstable_model_identity_for_durable_cache", observe)
        self.assertIn("mutable_alias_or_unknown", observe)

    def test_cache_eviction_is_explicit_and_revision_edits_do_not_delete_cache_rows(self) -> None:
        core = self.read("packages/fount/lib/fount/persistence/analysis.ex")
        guide = self.read("packages/fount_intelligence/guides/durable-analysis.md")
        self.assertIn("def evict_cache", core)
        self.assertIn("never called by revision edits", core)
        self.assertIn("does **not** delete analysis runs", guide)
        persistence = self.read("packages/fount/lib/fount/persistence.ex")
        self.assertNotIn("analysis_measurement_results", persistence)

    def test_recomputation_composes_existing_pure_frontiers(self) -> None:
        source = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/recomputation.ex"
        )
        self.assertIn("Temporal.recomputation_region", source)
        self.assertIn("Reader.recomputation_boundary", source)
        self.assertIn("Analysis.affected_records", source)
        self.assertIn('"revision_edit_deletes_cache_rows" => false', source)

    def test_workshop_durable_analysis_is_opt_in_and_existing_not_run_path_survives(self) -> None:
        bridge = self.read(
            "packages/fount_workshop/lib/fount_workshop/writing/intelligence.ex"
        )
        session = self.read("packages/fount_workshop/lib/fount_workshop/session.ex")
        self.assertIn("Keyword.get(opts, :durable_analysis, false)", bridge)
        self.assertIn('"observe_provider_not_configured"', bridge)
        self.assertIn("durable_analysis: false", session)
        self.assertIn("analysis_privacy_namespace", session)
        self.assertIn("analysis_candidate_id", bridge)

    def test_project_assets_are_data_only_host_gated_and_content_addressed(self) -> None:
        shell = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/persistence.ex"
        )
        self.assertIn("allow_project_assets", shell)
        self.assertIn("project_assets_disabled", shell)
        self.assertIn("CanonicalJSON.hash(content)", shell)
        self.assertIn("executable_analysis_asset_forbidden", shell)
        self.assertNotIn("Code.eval", shell)
        self.assertNotIn("Module.concat", shell)

    def test_writer_resume_regression_preserves_rejected_and_unchosen_history(self) -> None:
        source = self.read(
            "packages/fount_workshop/integration/phase_ten_resume_history_test.exs"
        )
        self.assertIn("Session.resume", source)
        self.assertIn('== "rejected"', source)
        self.assertIn('decisions[second["id"]] == "proposed"', source)
        self.assertIn("Analysis.runs_for_session", source)
        self.assertIn("head.revision.id == base.revision.id", source)

    def test_dependency_snapshots_remain_external_only_after_later_phases(self) -> None:
        changed = [
            "packages/fount/lib/fount/persistence/analysis.ex",
            "packages/fount_intelligence/lib/fount/intelligence/persistence.ex",
            "packages/fount_intelligence/lib/fount/intelligence/recomputation.ex",
            "packages/fount_workshop/lib/fount_workshop/writing/intelligence.ex",
        ]
        text = "\n".join(self.read(path) for path in changed)
        for direct in ["SystemOneSDK.", "Inference.complete", "ASM."]:
            self.assertNotIn(direct, text)


if __name__ == "__main__":
    unittest.main()