from __future__ import annotations

import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class PhaseFourteenSourceTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_phase_fourteen_surfaces_exist(self) -> None:
        required = [
            "packages/fount_workshop/lib/fount_workshop/research.ex",
            "packages/fount_workshop/lib/fount_workshop/note_triage.ex",
            "packages/fount_workshop/lib/fount_workshop/consequence_review.ex",
            "packages/fount_workshop/guides/research-notes-and-consequences.md",
            "packages/fount_workshop/examples/phase_fourteen/README.md",
            "packages/fount_workshop/test/writer_workflows/phase_fourteen_research_test.exs",
            "packages/fount_workshop/test/writer_workflows/phase_fourteen_notes_test.exs",
            "packages/fount_workshop/test/writer_workflows/phase_fourteen_consequence_test.exs",
            "packages/fount_workshop/test/writer_workflows/phase_fourteen_rebase_test.exs",
            "packages/fount_workshop/integration/phase_fourteen_research_notes_durability_test.exs",
        ]
        for path in required:
            self.assertTrue((ROOT / path).is_file(), path)

    def test_w07_records_provenance_fiction_status_and_untrusted_content_without_web_invention(self) -> None:
        source = self.read("packages/fount_workshop/lib/fount_workshop/research.ex")
        for token in [
            "sourced disputed unverified deliberately_fictionalized",
            "source writer_memory invention",
            '"trust", "untrusted_content"',
            '"instruction_authority", "none"',
            '"provider_export_allowed"',
            '"invented_references" => false',
            '"status" => "access_unavailable"',
        ]:
            self.assertIn(token, source)
        self.assertNotIn("HTTPoison", source)
        self.assertNotIn("Req.get", source)
        self.assertNotIn("System.cmd", source)

    def test_w08_keeps_raw_notes_decisions_and_exact_anchor_states(self) -> None:
        source = self.read("packages/fount_workshop/lib/fount_workshop/note_triage.ex")
        for token in [
            '"raw" => note["raw"]',
            '"source" => note["source"]',
            '"reaction"',
            '"interpretation"',
            '"requested_treatment"',
            "investigate experiment adopt defer decline ask_note_giver",
            "exact relocated_with_evidence ambiguous orphaned",
            '"multiple_exact_text_matches"',
            '"no_exact_identity_or_text_match"',
            "NoteConflicts.detect",
        ]:
            self.assertIn(token, source)
        self.assertNotIn("String.jaro", source)
        self.assertNotIn("fuzzy", source.lower())

    def test_w09_candidate_link_and_actual_consequence_review_are_visible(self) -> None:
        candidate_api = self.read("packages/fount_workshop/lib/fount_workshop/candidate_api.ex")
        triage = self.read("packages/fount_workshop/lib/fount_workshop/note_triage.ex")
        consequence = self.read("packages/fount_workshop/lib/fount_workshop/consequence_review.ex")
        comparison = self.read("packages/fount_workshop/lib/fount_workshop/comparison.ex")
        review = self.read("packages/fount_workshop/lib/fount_workshop/review.ex")
        self.assertIn("addresses_notes", candidate_api)
        self.assertIn("intelligence_lineage", candidate_api)
        self.assertIn("CandidateAPI.manual", triage)
        self.assertIn("local sequence whole_draft", triage)
        self.assertIn("Screenplay.diff", consequence)
        self.assertIn('"supported_dependencies"', consequence)
        self.assertIn('"uncertain_consequences"', consequence)
        self.assertIn('"unresolved_downstream_work"', consequence)
        self.assertIn('"unrelated_rewritten_scene_ids"', consequence)
        self.assertIn('"candidate_claims_are_evidence" => false', consequence)
        self.assertIn('"consequence_review" => ConsequenceReview.build(base, candidate)', comparison)
        self.assertIn('"comparison" => Comparison.compare(base, candidate)', review)

    def test_a06_a07_a08_and_concurrent_edit_regressions_are_written(self) -> None:
        files = [
            "packages/fount_workshop/test/writer_workflows/phase_fourteen_research_test.exs",
            "packages/fount_workshop/test/writer_workflows/phase_fourteen_notes_test.exs",
            "packages/fount_workshop/test/writer_workflows/phase_fourteen_consequence_test.exs",
            "packages/fount_workshop/test/writer_workflows/phase_fourteen_rebase_test.exs",
            "packages/fount_workshop/examples/phase_fourteen/README.md",
        ]
        text = "\n".join(self.read(path) for path in files)
        for token in [
            "A06",
            "A07",
            "A08",
            "Explain why she leaves",
            "Keep the mystery",
            "deliberately_fictionalized",
            "stale_revision",
            "rebase_conflicts",
            "Screenplay.undo",
        ]:
            self.assertIn(token, text)

    def test_session_records_remain_noncanonical_until_candidate_acceptance(self) -> None:
        research = self.read("packages/fount_workshop/lib/fount_workshop/research.ex")
        notes = self.read("packages/fount_workshop/lib/fount_workshop/note_triage.ex")
        self.assertIn('put_in(session, ["progress", "research"]', research)
        self.assertIn('put_in(session, ["progress", "note_triage"]', notes)
        self.assertNotIn("Screenplay.apply", research)
        self.assertNotIn("Screenplay.apply", notes)
        self.assertIn("CandidateAPI.manual", notes)

    def test_phase_fifteen_is_not_implemented_by_phase_fourteen_surface(self) -> None:
        paths = [
            "packages/fount_workshop/lib/fount_workshop/research.ex",
            "packages/fount_workshop/lib/fount_workshop/note_triage.ex",
            "packages/fount_workshop/lib/fount_workshop/consequence_review.ex",
            "packages/fount_workshop/guides/research-notes-and-consequences.md",
            "packages/fount_workshop/examples/phase_fourteen/README.md",
        ]
        text = "\n".join(self.read(path) for path in paths)
        self.assertNotIn("Phase 15", text)
        self.assertNotIn("usefulness report", text.lower())
        self.assertNotIn("clean share", text.lower())

    def test_dependency_boundaries_are_unchanged(self) -> None:
        mix = self.read("packages/fount_workshop/mix.exs")
        self.assertNotIn(":system_one_sdk", mix)
        self.assertIn('{:agent_session_manager, "~> 0.17.1"}', mix)
        self.assertIn('{:inference, "~> 0.5.0"}', mix)


if __name__ == "__main__":
    unittest.main()
