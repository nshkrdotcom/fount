from __future__ import annotations

import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class PhaseFifteenSourceTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_phase_fifteen_surfaces_exist(self) -> None:
        required = [
            "packages/fount_workshop/lib/fount_workshop/share.ex",
            "packages/fount_workshop/lib/fount_workshop/usefulness.ex",
            "packages/fount_workshop/guides/read-share-resume-and-usefulness.md",
            "packages/fount_workshop/examples/phase_fifteen/README.md",
            "packages/fount_workshop/test/writer_workflows/phase_fifteen_read_share_resume_test.exs",
            "packages/fount_workshop/test/writer_workflows/phase_fifteen_usefulness_test.exs",
            "packages/fount_workshop/integration/phase_fifteen_read_share_resume_test.exs",
        ]
        for path in required:
            self.assertTrue((ROOT / path).is_file(), path)

    def test_a09_human_read_packet_never_turns_tts_into_audience_evidence(self) -> None:
        source = self.read("packages/fount_workshop/lib/fount_workshop/table_read.ex")
        for token in [
            '"kind" => "fount.human_table_read"',
            '"speech_required" => false',
            '"audience_response_measured" => false',
            '"generated_transcript_is_audience_feedback" => false',
            '"synthesized_voice_is_performance_validation" => false',
            ':human_observer_required',
            '"script_wording"',
            '"reader_delivery"',
            '"listening_conditions"',
        ]:
            self.assertIn(token, source)

    def test_a11_share_is_accepted_source_only_and_surfaces_fidelity_losses(self) -> None:
        source = self.read("packages/fount_workshop/lib/fount_workshop/share.ex")
        for token in [
            "Editor.spec_ir",
            "Selection.selected_ids",
            '"private_notes"',
            '"boneyards"',
            '"omitted_scenes"',
            '"provider_metadata_included" => false',
            '"workshop_candidates_included" => false',
            '"unsupported_or_lossy"',
            "Screenplay.to_fdx",
            "Screenplay.export_fountain",
            ':clean_share_requires_whole_scenes',
        ]:
            self.assertIn(token, source)
        self.assertNotIn("Inference.complete", source)
        self.assertNotIn("Session.get", source)

    def test_a10_regression_preserves_stale_idempotent_and_resume_contracts(self) -> None:
        source = self.read(
            "packages/fount_workshop/test/writer_workflows/phase_fifteen_read_share_resume_test.exs"
        )
        for token in [
            "A09/A10/A11",
            "stale_revision",
            "Retrying the same writer decision is idempotent",
            "Session.resume_view",
            '== "accepted"',
            '== "rejected"',
            '== "proposed"',
            "ContinuationStore.head",
        ]:
            self.assertIn(token, source)

    def test_a12_usefulness_keeps_conditions_and_dimensions_separate_without_scoring(self) -> None:
        source = self.read("packages/fount_workshop/lib/fount_workshop/usefulness.ex")
        test = self.read(
            "packages/fount_workshop/test/writer_workflows/phase_fifteen_usefulness_test.exs"
        )
        for token in [
            "human_only basic_llm fount_assisted",
            "positive neutral negative",
            '"aggregate_screenplay_score" => false',
            '"automatic_winner" => false',
            '"expert_endorsement" => false',
            '"representative_sample" => false',
            '"acceptance_rate_equals_quality" => false',
        ]:
            self.assertIn(token, source)
        self.assertIn('"kept_original" => true', test)
        self.assertIn('human_study: "not_run"', test)

    def test_existing_read_command_is_extended_instead_of_replaced(self) -> None:
        cli = self.read("packages/fount_workshop/lib/fount_workshop/cli.ex")
        self.assertIn('FountWorkshop.TableRead.export(', cli)
        self.assertIn('FountWorkshop.TableRead.export_packet(', cli)
        self.assertIn('Share.export(model, selection', cli)
        self.assertIn('Path.join(opts[:output], "table-read.json")', cli)
        self.assertIn('Path.join(opts[:output], "table-read.html")', cli)

    def test_actual_inference_facade_is_used_only_as_documented_baseline(self) -> None:
        guide = self.read("packages/fount_workshop/guides/read-share-resume-and-usefulness.md")
        self.assertIn("Inference.client!", guide)
        self.assertIn("Inference.complete(client, prompt)", guide)
        self.assertIn("Inference.Response.text(response)", guide)
        for token in ["capture", "explore", "revise", "compare", "accept/reject", "export", "resume"]:
            self.assertIn(token, guide.lower())

    def test_phase_sixteen_is_not_implemented(self) -> None:
        paths = [
            "packages/fount_workshop/lib/fount_workshop/share.ex",
            "packages/fount_workshop/lib/fount_workshop/usefulness.ex",
            "packages/fount_workshop/guides/read-share-resume-and-usefulness.md",
            "packages/fount_workshop/examples/phase_fifteen/README.md",
        ]
        text = "\n".join(self.read(path) for path in paths)
        self.assertNotIn("Phase 16", text)
        self.assertNotIn("final integration", text.lower())

    def test_dependency_boundaries_are_unchanged(self) -> None:
        mix = self.read("packages/fount_workshop/mix.exs")
        self.assertNotIn(":system_one_sdk", mix)
        self.assertIn('{:agent_session_manager, "~> 0.17.1"}', mix)
        self.assertIn('{:inference, "~> 0.5.0"}', mix)


if __name__ == "__main__":
    unittest.main()
