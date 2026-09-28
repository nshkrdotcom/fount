from __future__ import annotations

import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class PhaseTwelveSourceTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_discovery_and_public_writer_surfaces_exist(self) -> None:
        required = [
            "packages/fount_workshop/lib/fount_workshop/discovery.ex",
            "packages/fount_workshop/guides/discovery-and-scene-exploration.md",
            "packages/fount_workshop/test/writer_workflows/phase_twelve_discovery_test.exs",
            "packages/fount_workshop/test/writer_workflows/phase_twelve_a01_demo_test.exs",
            "packages/fount_workshop/test/writer_workflows/phase_twelve_inspect_test.exs",
            "packages/fount_workshop/test/writer_workflows/phase_twelve_scene_exploration_test.exs",
            "packages/fount_workshop/examples/phase_twelve/README.md",
            "packages/fount_workshop/lib/mix/tasks/fount.open.ex",
            "packages/fount_workshop/lib/mix/tasks/fount.fragment.ex",
            "packages/fount_workshop/lib/mix/tasks/fount.manual.ex",
            "packages/fount_workshop/lib/mix/tasks/fount.edit.ex",
        ]
        for path in required:
            self.assertTrue((ROOT / path).is_file(), path)

    def test_four_writer_modes_and_legacy_diagnose_are_explicit(self) -> None:
        schema = json.loads(self.read("packages/fount/priv/writing_contracts/workflow.schema.json"))
        modes = schema["properties"]["mode"]["enum"]
        for mode in ["draft", "explore", "inspect", "revise"]:
            self.assertIn(mode, modes)
        self.assertIn("diagnose", modes)
        discovery = self.read("packages/fount_workshop/lib/fount_workshop/discovery.ex")
        self.assertIn('defp public_mode("diagnose"), do: "inspect"', discovery)
        self.assertIn('"mode_history"', discovery)

    def test_provider_free_open_and_manual_candidate_do_not_require_inference(self) -> None:
        session = self.read("packages/fount_workshop/lib/fount_workshop/session.ex")
        candidate_api = self.read("packages/fount_workshop/lib/fount_workshop/candidate_api.ex")
        candidate = self.read("packages/fount_workshop/lib/fount_workshop/candidate.ex")
        self.assertIn("def open(model, request, services", session)
        open_body = session.split("def open(model, request, services", 1)[1].split("def start", 1)[0]
        self.assertNotIn("services(services)", open_body)
        self.assertNotIn("services[:inference]", open_body)
        self.assertIn("def manual(session_id, operations, services", candidate)
        manual_body = candidate_api.split("def manual(session_id, operations, services", 1)[1].split("def manual(_session_id", 1)[0]
        self.assertNotIn("services[:inference]", manual_body)
        self.assertIn('writer_edit: true', manual_body)

    def test_discovery_state_is_noncanonical_and_tracks_brief_fragments_and_card_proposals(self) -> None:
        source = self.read("packages/fount_workshop/lib/fount_workshop/discovery.ex")
        for token in [
            '"brief"',
            '"brief_history"',
            '"fragments"',
            '"card_reorders"',
            '"decisions"',
            '"pending_question"',
            '"selected_candidate_id"',
            'def reverse_outline',
            '"function_status"',
            '"interpretation"',
            '"changes_canon" => false',
            'def propose_reorder',
            'def retire_fragment',
            'def adopt_fragment',
        ]:
            self.assertIn(token, source)
        self.assertNotIn("Fount.Screenplay.apply", source)

    def test_treatment_contract_requires_materially_distinct_route_metadata(self) -> None:
        request = self.read("packages/fount_workshop/lib/fount_workshop/request.ex")
        strategy = self.read("packages/fount_workshop/lib/fount_workshop/strategy.ex")
        for token in ["treatments", "allow_brief_departure", "mechanism_kind", "action", "revelation", "relationship"]:
            self.assertIn(token, request + strategy)
        self.assertIn(":treatment_routes_not_honored", strategy)
        self.assertIn(":treatment_tradeoff_required", strategy)
        self.assertIn("No universal act formula, quality score, winner", strategy)

    def test_cli_exposes_provider_free_capture_edit_and_decisions(self) -> None:
        cli = self.read("packages/fount_workshop/lib/fount_workshop/cli.ex")
        for command in ["open", "fragment", "brief", "mode", "outline", "reorder", "manual", "edit", "decide"]:
            self.assertIn(f'"{command}"', cli)
        paid_block = cli.split("paid =", 1)[1].split("clients =", 1)[0]
        for command in ["open", "fragment", "brief", "mode", "outline", "reorder", "manual", "edit", "decide"]:
            self.assertNotIn(f'command == "{command}"', paid_block)

    def test_phase_twelve_examples_are_valid_json_and_stop_before_phase_thirteen(self) -> None:
        fixtures = ROOT / "packages/fount_workshop/examples/phase_twelve"
        for path in fixtures.glob("*.json"):
            json.loads(path.read_text(encoding="utf-8"))
        phase12_paths = [
            ROOT / "packages/fount_workshop/lib/fount_workshop/discovery.ex",
            ROOT / "packages/fount_workshop/guides/discovery-and-scene-exploration.md",
            ROOT / "packages/fount_workshop/test/writer_workflows/phase_twelve_discovery_test.exs",
            ROOT / "packages/fount_workshop/test/writer_workflows/phase_twelve_a01_demo_test.exs",
            ROOT / "packages/fount_workshop/test/writer_workflows/phase_twelve_inspect_test.exs",
            ROOT / "packages/fount_workshop/test/writer_workflows/phase_twelve_scene_exploration_test.exs",
        ]
        text = "\n".join(path.read_text(encoding="utf-8") for path in phase12_paths)
        self.assertNotIn("Phase 13", text)
        self.assertNotIn("rehearsal", text.lower())
        self.assertNotIn("voice exemplar", text.lower())


if __name__ == "__main__":
    unittest.main()
