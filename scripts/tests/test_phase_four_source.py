from __future__ import annotations

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
INTEL = ROOT / "packages" / "fount_intelligence"


class PhaseFourSourceTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_phase_four_modules_and_writer_guide_exist(self) -> None:
        required = [
            "packages/fount_intelligence/lib/fount/intelligence/temporal.ex",
            "packages/fount_intelligence/lib/fount/intelligence/reader.ex",
            "packages/fount_intelligence/lib/fount/intelligence/reader/event.ex",
            "packages/fount_intelligence/lib/fount/intelligence/reader/state.ex",
            "packages/fount_intelligence/lib/fount/intelligence/reader/snapshot.ex",
            "packages/fount_intelligence/guides/temporal-and-reader.md",
            "packages/fount_intelligence/examples/phase_four.exs",
            "packages/fount_intelligence/test/temporal_views_test.exs",
            "packages/fount_intelligence/test/reader_forward_test.exs",
            "packages/fount_intelligence/test/reader_story_world_differential_test.exs",
        ]
        for path in required:
            self.assertTrue((ROOT / path).is_file(), path)

    def test_pure_phase_four_source_does_not_cross_effect_boundaries(self) -> None:
        sources = list((INTEL / "lib" / "fount" / "intelligence" / "reader").glob("*.ex"))
        sources += [INTEL / "lib" / "fount" / "intelligence" / "reader.ex"]
        sources += [INTEL / "lib" / "fount" / "intelligence" / "temporal.ex"]
        text = "\n".join(path.read_text(encoding="utf-8") for path in sources)

        forbidden = [
            "SystemOneSDK",
            "Inference.",
            "Fount.Repo",
            "Fount.Persistence",
            "Fount.Intelligence.Acquisition",
            "Fount.Intelligence.Playbooks",
            "File.",
            "System.get_env",
            "DateTime.utc_now",
            "Fount.ID.v4",
        ]
        for token in forbidden:
            self.assertNotIn(token, text, token)

    def test_reader_has_forward_leak_and_private_material_guards(self) -> None:
        source = self.read("packages/fount_intelligence/lib/fount/intelligence/reader.ex")
        self.assertIn('Fount.Selection.select(screenplay, %{"whole_screenplay" => true})', source)
        self.assertIn(":future_reader_evidence", source)
        self.assertIn('visibility: "private"', source)
        self.assertIn('"presentation_suffix"', source)
        self.assertIn("def reduce(", source)

    def test_temporal_views_preserve_partial_story_time(self) -> None:
        source = self.read("packages/fount_intelligence/lib/fount/intelligence/temporal.ex")
        story_time = self.read(
            "packages/fount_intelligence/lib/fount/intelligence/story_world/story_time.ex"
        )
        self.assertIn('"diegetic_story_time_partial"', source)
        self.assertIn("StoryTime.connected_nodes", source)
        self.assertIn("def connected_nodes", story_time)
        self.assertIn('"story_time_connected_region"', source)

    def test_phase_four_docs_do_not_claim_human_validation(self) -> None:
        guide = self.read("packages/fount_intelligence/guides/temporal-and-reader.md")
        verification = self.read("packages/fount_intelligence/guides/verification.md")
        self.assertIn("never manufactures a human-calibrated", guide)
        self.assertIn("must not be fabricated", verification)


if __name__ == "__main__":
    unittest.main()
