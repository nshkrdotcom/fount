"""Exercise launcher commands without installing dependencies or starting a server."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'dev.sh'


class DevLauncherTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / 'checkout with spaces'
        for part in ('scripts', 'apps/fount_web', 'packages/fount_workshop'):
            (self.repo / part).mkdir(parents=True)
        if SCRIPT.exists():
            shutil.copy2(SCRIPT, self.repo / 'scripts/dev.sh')
        sdk = self.root / 'system_one_sdk/packages/system_one_sdk'
        sdk.mkdir(parents=True)
        (sdk / 'mix.exs').write_text('# SDK fixture')
        self.log = self.root / 'commands.jsonl'
        bindir = self.root / 'bin'
        bindir.mkdir()
        stub = '''#!/usr/bin/env python3
import json,os,sys
with open(os.environ['DEV_TEST_LOG'],'a') as out:
 out.write(json.dumps(dict(tool=os.path.basename(sys.argv[0]),args=sys.argv[1:],cwd=os.getcwd(),sdk=os.environ.get('FOUNT_SYSTEM_ONE_SDK_PATH'),mode=os.environ.get('MIX_ENV'),observe=os.environ.get('FOUNT_OBSERVE_MODE'),port=os.environ.get('PORT'),database=os.environ.get('FOUNT_DATABASE_URL'),package=os.environ.get('FOUNT_PACKAGE_BUILD')))+'\\n')
if sys.argv[1:]==['deps.get'] and os.environ.get('DEV_TEST_FAIL'): sys.exit(7)
if sys.argv[1:3]==['run','--no-start']:
 if os.environ.get('DEV_TEST_DB_FAIL'): sys.exit(6)
 with open(sys.argv[-1],'w') as out: out.write(os.environ.get('FOUNT_DATABASE_URL','ecto://fixture@localhost:5433/fount_dev'))
'''
        for tool in ('mix', 'npm'):
            p = bindir / tool
            p.write_text(stub)
            p.chmod(0o755)
        self.env = {**os.environ, 'PATH': str(bindir)+os.pathsep+os.environ['PATH'], 'DEV_TEST_LOG': str(self.log), 'MIX_ENV': 'prod', 'FOUNT_PACKAGE_BUILD': '1', 'FOUNT_OBSERVE_MODE': 'system_one'}
        for key in ('FOUNT_SYSTEM_ONE_SDK_PATH', 'FOUNT_DATABASE_URL', 'PORT'):
            self.env.pop(key, None)

    def run_script(self, *args):
        return subprocess.run(['bash', str(self.repo/'scripts/dev.sh'), *args], cwd=self.root, env=self.env, text=True, capture_output=True)

    def records(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_help_does_not_run_mix(self):
        p = self.run_script('--help')
        self.assertEqual(p.returncode, 0, p.stderr)
        for word in ('setup', 'start', 'up', '--sdk-path', '--database-url', '--port'):
            self.assertIn(word, p.stdout)
        self.assertFalse(self.log.exists())

    def test_setup_uses_hex_sdk_and_creates_before_migrating(self):
        p = self.run_script('setup')
        self.assertEqual(p.returncode, 0, p.stderr)
        r = self.records()
        self.assertEqual(r[0]['args'], ['deps.get'])
        self.assertEqual(r[1]['args'][:2], ['run', '--no-start'])
        self.assertEqual([x['args'] for x in r[2:]], [['ecto.create', '-r', 'Fount.Repo'], ['fount_web.migrate'], ['ci'], ['assets.setup'], ['assets.build']])
        self.assertFalse(Path(r[1]['args'][-1]).exists())
        self.assertTrue(all(x['mode']=='dev' and x['observe']=='sandbox' and x['package'] is None for x in r))
        self.assertTrue(all(x['sdk'] is None for x in r))
        self.assertFalse(any(x['args']==['phx.server'] for x in r))

    def test_up_starts_foreground_and_accepts_options(self):
        p = self.run_script('up', '--port', '4057', '--database-url', 'ecto://localhost/custom_dev')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(self.records()[-1]['args'], ['phx.server'])
        self.assertTrue(all(x['port']=='4057' and x['database']=='ecto://localhost/custom_dev' for x in self.records()))

    def test_explicit_sdk_override_is_passed_to_mix(self):
        sdk = self.root / 'system_one_sdk/packages/system_one_sdk'
        p = self.run_script('setup', '--sdk-path', str(sdk))
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertTrue(all(x['sdk'] == str(sdk) for x in self.records()))

    def test_setup_does_not_require_a_sibling_checkout(self):
        shutil.rmtree(self.root / 'system_one_sdk')
        p = self.run_script('setup')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertTrue(all(x['sdk'] is None for x in self.records()))

    def test_bad_sdk_fails_before_mix(self):
        p = self.run_script('setup', '--sdk-path', str(self.root/'missing'))
        self.assertNotEqual(p.returncode, 0)
        self.assertIn('--sdk-path', p.stderr)
        self.assertFalse(self.log.exists())

    def test_dependency_failure_stops_before_database_or_server(self):
        self.env['DEV_TEST_FAIL'] = '1'
        p = self.run_script('up')
        self.assertEqual(p.returncode, 7, p.stderr)
        self.assertEqual(len(self.records()), 1)
        self.assertIn('dependencies', p.stderr.lower())

    def test_invalid_port_and_unknown_options(self):
        for args in [('start', '--port', '0'), ('start', '--port', '65536'), ('--unknown',)]:
            with self.subTest(args=args):
                p=self.run_script(*args)
                self.assertNotEqual(p.returncode,0)
                self.assertFalse(self.log.exists())

    def test_start_resolves_database_before_compilation_and_server(self):
        p = self.run_script('start')
        self.assertEqual(p.returncode, 0, p.stderr)
        r = self.records()
        self.assertEqual(r[0]['args'][:2], ['run', '--no-start'])
        self.assertEqual([x['args'] for x in r[1:]], [['compile'], ['phx.server']])
        self.assertEqual(r[-1]['database'], 'ecto://fixture@localhost:5433/fount_dev')

    def test_database_preflight_failure_stops_before_migrations_or_server(self):
        self.env['DEV_TEST_DB_FAIL'] = '1'
        p = self.run_script('up')
        self.assertEqual(p.returncode, 6)
        r = self.records()
        self.assertEqual(len(r), 2)
        self.assertFalse(Path(r[-1]['args'][-1]).exists())
        self.assertIn('PostgreSQL connection', p.stderr)

    def test_environment_url_is_preserved_and_cli_overrides_it(self):
        self.env['FOUNT_DATABASE_URL'] = 'ecto://localhost/environment_dev'
        p = self.run_script('start', '--database-url', 'ecto://localhost/cli_dev')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertTrue(all(x['database']=='ecto://localhost/cli_dev' for x in self.records()))
