"""Phase 1 structural checks only; these are not an Elixir compiler or runtime gate."""
import json, os, unittest
from pathlib import Path
ROOT=Path(os.environ.get('FOUNT_SOURCE', str(Path(__file__).resolve().parents[2])))
class PhaseSource(unittest.TestCase):
    def test_exact_package_set(self):
        self.assertEqual({p.name for p in (ROOT/'packages').iterdir() if p.is_dir()}, {'fount','fount_observe','fount_intelligence','fount_workshop'})
    def test_observe_contracts_exist(self):
        for name in ['question','request','observation','measurement_result','distribution','target_ref','evidence_ref','context','error','executor','lens','registry','sandbox']:
            self.assertTrue((ROOT/f'packages/fount_observe/lib/fount/observe/{name}.ex').is_file(), name)
    def test_provider_and_generation_boundaries(self):
        for p in (ROOT/'packages').glob('*/lib/**/*.ex'):
            text=p.read_text()
            if 'SystemOneSDK.' in text:
                self.assertIn('/fount_observe/lib/fount/observe/providers/system_one', str(p), str(p))
            if 'Inference.' in text:
                self.assertIn('/fount_workshop/', str(p), str(p))
    def test_no_superseded_runtime_references(self):
        for p in (ROOT/'packages').glob('*/lib/**/*.ex'):
            self.assertNotIn('FountProbe', p.read_text(), str(p))
    def test_lens_assets_have_content_identity_not_versions(self):
        paths=list((ROOT/'packages/fount_observe/priv/lenses').glob('*.json'))
        self.assertGreaterEqual(len(paths), 10)
        for p in paths:
            data=json.loads(p.read_text())
            self.assertNotIn('version', data)
            self.assertIn('context_contract', data)
            self.assertIn('sensor', data)
            self.assertIn('id', data)
    def test_architecture_gate_exists(self):
        self.assertTrue((ROOT/'packages/fount_intelligence/lib/mix/tasks/fount.architecture.ex').is_file())
if __name__ == '__main__': unittest.main()
