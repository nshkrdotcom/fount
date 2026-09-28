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
class PhaseOneApprovalSafetySource(unittest.TestCase):
    def test_core_approval_contract_and_no_run_package(self):
        for rel in [
            'packages/fount/lib/fount/writing/principal.ex',
            'packages/fount/lib/fount/writing/authority.ex',
            'packages/fount/lib/fount/writing/review.ex',
            'packages/fount/lib/fount/writing/approval.ex',
            'packages/fount/lib/fount/writing/check_set.ex',
            'packages/fount/priv/repo/migrations/20260928000000_authorize_canonical_acceptance.exs',
        ]:
            self.assertTrue((ROOT/rel).is_file(), rel)
        self.assertFalse((ROOT/'packages/fount_run').exists())

    def test_only_genesis_and_authorized_acceptance_move_head(self):
        source=(ROOT/'packages/fount/lib/fount/persistence.ex').read_text()
        self.assertIn('rollback(repo, :approval_required)', source)
        self.assertIn('def save_edit_candidate', source)
        self.assertIn('Keyword.get(opts, :approval)', source)
        self.assertIn('Keyword.get(opts, :authority)', source)
        calls=[line.strip() for line in source.splitlines() if 'set_head(repo,' in line and not line.lstrip().startswith('defp ')]
        self.assertEqual(len(calls), 2, calls)
        self.assertTrue(any('root.id' in line for line in calls), calls)
        self.assertTrue(any('context.model.id' in line for line in calls), calls)

    def test_required_check_and_stable_approval_audit_are_persisted(self):
        persistence=(ROOT/'packages/fount/lib/fount/persistence.ex').read_text()
        gate=(ROOT/'packages/fount/lib/fount/writing/review_gate.ex').read_text()
        migration=(ROOT/'packages/fount/priv/repo/migrations/20260928000000_authorize_canonical_acceptance.exs').read_text()
        self.assertIn('check_set_fingerprint', persistence)
        self.assertIn('approval_hash', persistence)
        self.assertIn('automated_override_forbidden', gate)
        self.assertIn('required_check_not_passing', gate)
        self.assertIn('acceptance_approval_once', migration)
        self.assertIn("'historical'", migration)

    def test_legacy_actor_review_shape_is_not_writable(self):
        for rel in [
            'packages/fount_workshop/lib/fount_workshop.ex',
            'packages/fount_workshop/lib/fount_workshop/acceptance.ex',
            'packages/fount_workshop/lib/fount_workshop/review.ex',
        ]:
            text=(ROOT/rel).read_text()
            self.assertIn(':authorized_approval_required', text, rel)
        cli=(ROOT/'packages/fount_workshop/lib/fount_workshop/cli.ex').read_text()
        self.assertIn('principal_type: :string', cli)
        self.assertIn('approval_id: :string', cli)

if __name__ == '__main__': unittest.main()
