"""Phase 2 source/asset checks, NOT Elixir compilation or runtime verification."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
OBSERVE = ROOT / 'packages' / 'fount_observe'


def digest(value):
    # This fixture uses ASCII strings, integer schema limits and no floats in its
    # identity. Check the actual Elixir CanonicalJSON path in the ExUnit fixture test.
    data = json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False)
    return hashlib.sha256(data.encode()).hexdigest()


class PhaseTwoSourceTests(unittest.TestCase):
    def test_required_implementation_files_are_present(self):
        for name in ('output_contract', 'measurement_spec', 'fingerprint', 'calibration',
                     'recording', 'resources', 'scene_question', 'cache/ets'):
            self.assertTrue((OBSERVE / 'lib/fount/observe' / (name + '.ex')).is_file(), name)

    def test_all_observe_assets_are_json_objects(self):
        paths = list((OBSERVE / 'priv').rglob('*.json'))
        self.assertGreaterEqual(len(paths), 12)
        for path in paths:
            self.assertIsInstance(json.loads(path.read_text()), dict, str(path))

    def test_fixture_semantic_input_identity(self):
        fixture = json.loads((OBSERVE / 'priv/fixtures/scene_visibility.json').read_text())['fixtures'][0]
        self.assertEqual(fixture['input_sha256'], digest({
            'state': {'text': 'Mara pockets a key.'}, 'context': {'slots': {}}}))
        self.assertEqual(fixture['projection_id'], 'explicit_state')

    def test_fixture_question_identity(self):
        fixture = json.loads((OBSERVE / 'priv/fixtures/scene_visibility.json').read_text())['fixtures'][0]
        self.assertEqual(fixture['questions_sha256'], digest([{
            'key': 'visible', 'kind': 'noul', 'instructions': 'Is the action observable?',
            'criteria': [], 'levels': [], 'extra': {}}]))

    def test_fixture_output_contract_identity(self):
        def obj(properties):
            return {'type': 'object', 'properties': properties,
                    'required': sorted(properties), 'additionalProperties': False}
        number = {'type': 'number', 'minimum': 0, 'maximum': 1}
        shape = obj({'type': {'type': 'string', 'const': 'noul'},
                     'probability': number,
                     'probabilities': obj({'true': number, 'false': number})})
        fixture = json.loads((OBSERVE / 'priv/fixtures/scene_visibility.json').read_text())['fixtures'][0]
        self.assertEqual(fixture['output_contracts'], [{'key': 'visible', 'sha256': digest(shape)}])

    def test_identity_calibration_makes_no_empirical_claim(self):
        value = json.loads((OBSERVE / 'priv/calibrations/identity.json').read_text())
        self.assertEqual(value['method'], 'identity')
        self.assertEqual(value['validation'], 'identity_not_empirical')
        self.assertNotIn('temperature', value)
        self.assertNotIn('version', value)

    def test_runtime_regression_sources_and_demos_are_included(self):
        for suffix in ('contracts', 'execution', 'sources', 'provider', 'scene_question'):
            path = OBSERVE / 'test' / ('phase_two_' + suffix + '_test.exs')
            self.assertTrue(path.is_file(), str(path))
        for name in ('phase_two.exs', 'fixture_file.exs', 'live.exs'):
            self.assertTrue((OBSERVE / 'examples' / name).is_file(), name)
        live = (OBSERVE / 'examples/live.exs').read_text()
        self.assertIn('FOUNT_OBSERVE_LIVE', live)
        self.assertIn('max_provider_requests: 1', live)

    def test_docs_state_runtime_is_recorded(self):
        guide = (OBSERVE / 'guides/measurement-substrate.md').read_text()
        self.assertIn('PHASE_02_RUNTIME_QC_REPORT.md', guide)
        self.assertRegex(guide, r'No human\s+usefulness')


if __name__ == '__main__':
    unittest.main()
