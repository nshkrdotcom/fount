from __future__ import annotations

import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class PhaseThirteenSourceTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_phase_thirteen_surfaces_exist(self) -> None:
        required = [
            "packages/fount_workshop/lib/fount_workshop/rehearsal.ex",
            "packages/fount_workshop/lib/fount_workshop/comparison.ex",
            "packages/fount_workshop/lib/fount_workshop/writing/voice_protection.ex",
            "packages/fount_workshop/guides/cinematic-revision-rehearsal-and-voice.md",
            "packages/fount_workshop/examples/phase_thirteen/README.md",
            "packages/fount_workshop/test/writer_workflows/phase_thirteen_voice_test.exs",
            "packages/fount_workshop/test/writer_workflows/phase_thirteen_rehearsal_test.exs",
            "packages/fount_workshop/test/writer_workflows/phase_thirteen_comparison_test.exs",
            "packages/fount_workshop/test/writer_workflows/phase_thirteen_pass_profiles_test.exs",
        ]
        for path in required:
            self.assertTrue((ROOT / path).is_file(), path)

    def test_w04_profiles_cover_visual_sound_space_stillness_and_transition(self) -> None:
        request = self.read("packages/fount_workshop/lib/fount_workshop/request.ex")
        legacy = self.read("packages/fount_workshop/lib/fount_workshop/pass.ex")
        prep = self.read("packages/fount_workshop/lib/fount_workshop/writing/preparation.ex")
        combined = request + legacy + prep
        for profile in ["action_visual", "sound_space", "cinematic_rhythm", "transition"]:
            self.assertIn(profile, combined)
            path = ROOT / "packages/fount_workshop/priv/writing_profiles" / f"{profile}.json"
            self.assertTrue(path.is_file(), profile)
            json.loads(path.read_text(encoding="utf-8"))
        self.assertIn("intentional stillness", prep)
        self.assertIn("offscreen", prep.lower())
        self.assertIn("voiceover", prep.lower())
        self.assertIn("camera directions", prep.lower())

    def test_w06_exact_voice_protection_uses_existing_deterministic_pin_path(self) -> None:
        voice = self.read("packages/fount_workshop/lib/fount_workshop/writing/voice_protection.ex")
        request = self.read("packages/fount_workshop/lib/fount_workshop/request.ex")
        context = self.read("packages/fount_workshop/lib/fount_workshop/writing/context.ex")
        generation = self.read("packages/fount_workshop/lib/fount_workshop/writing/generation.ex")
        self.assertIn('"kind" => "pin_text"', voice)
        self.assertIn('"severity" => "required"', voice)
        self.assertIn("Constraints.deterministic", voice)
        self.assertIn("VoiceProtection.resolve_constraints", request)
        self.assertIn('"voice_protection"', context)
        self.assertIn("do not silently translate or normalize", generation.lower())
        self.assertIn("language or cultural authenticity", voice)

    def test_w05_rehearsal_is_session_only_and_only_adopted_material_enters_generation_context(self) -> None:
        rehearsal = self.read("packages/fount_workshop/lib/fount_workshop/rehearsal.ex")
        session = self.read("packages/fount_workshop/lib/fount_workshop/session.ex")
        self.assertIn('"canonical" => false', rehearsal)
        self.assertIn('&1["status"] == "adopted"', rehearsal)
        self.assertIn("explicitly_adopted_rehearsal", rehearsal)
        self.assertIn("Rehearsal.generation_context(session)", session)
        self.assertNotIn("Fount.Screenplay.apply", rehearsal)
        self.assertNotIn("Fount.Intelligence.StoryWorld", rehearsal)

    def test_actual_candidate_comparison_does_not_trust_generator_summary(self) -> None:
        comparison = self.read("packages/fount_workshop/lib/fount_workshop/comparison.ex")
        self.assertIn("Screenplay.diff", comparison)
        self.assertIn('"action_changes"', comparison)
        self.assertIn('"language_changes"', comparison)
        self.assertIn('"protected_text_checks"', comparison)
        self.assertIn('"generator_claim_is_evidence" => false', comparison)
        self.assertIn('"automatic_winner" => false', comparison)

    def test_a02_a04_a05_regressions_are_written_and_phase_fourteen_is_not_started(self) -> None:
        paths = [
            ROOT / "packages/fount_workshop/test/writer_workflows/phase_thirteen_comparison_test.exs",
            ROOT / "packages/fount_workshop/test/writer_workflows/phase_thirteen_voice_test.exs",
            ROOT / "packages/fount_workshop/test/writer_workflows/phase_thirteen_rehearsal_test.exs",
            ROOT / "packages/fount_workshop/guides/cinematic-revision-rehearsal-and-voice.md",
        ]
        text = "\n".join(path.read_text(encoding="utf-8") for path in paths)
        for token in ["A02", "A04", "A05", "Not today. Not today.", "stole a boat"]:
            self.assertIn(token, text)
        self.assertNotIn("Phase 14", text)
        self.assertNotIn("table read implementation", text.lower())

    def test_workshop_preserves_existing_dependency_boundary(self) -> None:
        mix = self.read("packages/fount_workshop/mix.exs")
        self.assertNotIn(":system_one_sdk", mix)
        self.assertIn('{:agent_session_manager, "~> 0.17.3"}', mix)
        self.assertIn('{:inference, "~> 0.5.1"}', mix)


if __name__ == "__main__":
    unittest.main()
