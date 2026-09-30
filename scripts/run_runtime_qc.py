#!/usr/bin/env python3
"""Run deterministic UI runtime QC without an interactive review step.

The runtime agent repairs failures and reruns this complete command inventory.
Reports never certify a changed source tree. Database URLs are not logged.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = ['fount', 'fount_observe', 'fount_intelligence', 'fount_workshop', 'fount_run']
PHASE_REQUIRED_FOCUSED = {
    7: [
        'test/fount_web/phase07_workflow_management_test.exs',
        'integration/phase07_workflow_management_test.exs',
    ],
}
LADDER = [
    ['mix', 'setup'],
    ['mix', 'format', '--check-formatted'],
    ['mix', 'deps.unlock', '--check-unused'],
    ['mix', 'blitz.workspace', 'format', '--check-formatted'],
    ['mix', 'blitz.workspace', 'lock_check'],
    ['mix', 'blitz.workspace', 'compile'],
    ['mix', 'test', '--warnings-as-errors'],
    ['mix', 'fount.architecture'],
    ['mix', 'blitz.workspace', 'credo', '--strict'],
    ['mix', 'blitz.workspace', 'dialyzer'],
    ['mix', 'blitz.workspace', 'docs'],
    ['mix', 'ci'],
    ['python3', '-m', 'unittest', 'discover', '-s', 'scripts/tests', '-p', 'test_*.py'],
    ['python3', 'scripts/final_acceptance.py'],
    ['git', 'diff', '--check'],
]


def identity():
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    diff = subprocess.check_output(['git', 'diff', 'HEAD', '--binary'], cwd=ROOT)
    untracked = subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard'], cwd=ROOT, text=True)
    digest = hashlib.sha256(diff)
    for name in sorted(untracked.splitlines()):
        digest.update(name.encode())
        digest.update((ROOT / name).read_bytes())
    return {'commit': head, 'working_tree_sha256': digest.hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase', type=int, choices=range(4, 9), required=True)
    parser.add_argument('--output', type=Path, required=True, help='New log directory outside repositories')
    args = parser.parse_args()
    output = args.output.resolve()
    if output.is_relative_to(ROOT):
        parser.error('Keep QC logs outside the source repository')
    output.mkdir(parents=True, exist_ok=False)
    env = os.environ.copy()
    env['FOUNT_OBSERVE_MODE'] = 'sandbox'
    env.pop('PHX_SERVER', None)
    env.pop('MIX_ENV', None)
    env.pop('FOUNT_PACKAGE_BUILD', None)
    env['FOUNT_DATABASE_URL'] = env.get('FOUNT_DATABASE_URL', 'ecto://postgres:postgres@localhost/fount_phase_qc_test')
    browser_url = env.get('FOUNT_BROWSER_DATABASE_URL', 'ecto://postgres:postgres@localhost/fount_phase_qc_browser')
    if browser_url == env['FOUNT_DATABASE_URL']:
        parser.error('Browser and ExUnit databases must be separate')
    start_identity = identity()
    report = {'phase': args.phase, 'source': start_identity, 'results': []}
    app = ROOT / 'apps/fount_web'

    def run(command, cwd=ROOT, overrides=None):
        current_env = env | (overrides or {})
        number = len(report['results'])
        start = time.monotonic()
        logfile = output / f'{number:02d}.log'
        with logfile.open('w') as stream:
            result = subprocess.run(command, cwd=cwd, env=current_env, stdout=stream, stderr=subprocess.STDOUT)
        row = {'cwd': str(cwd), 'command': command, 'environment': {k: v for k, v in (overrides or {}).items() if k != 'FOUNT_DATABASE_URL'},
               'exit_code': result.returncode, 'seconds': round(time.monotonic() - start, 2), 'log': logfile.name}
        report['results'].append(row)
        (output / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
        print(f"{number:02d}: exit {result.returncode}: {' '.join(command)}", flush=True)
        return result.returncode

    run(['mix', 'setup'])
    run(['mix', 'ecto.create', '-r', 'Fount.Repo'], app, {'MIX_ENV': 'test'})
    migrated = run(['mix', 'fount_web.migrate'], app, {'MIX_ENV': 'test'}) == 0
    if args.phase == 4:
        focused = ['test/fount_web/core_components_test.exs', 'test/fount_web/screenplay_renderer_test.exs',
                   'test/fount_web/screenplay_index_test.exs', 'test/fount_web/diff_viewer_test.exs',
                   'test/fount_web/phase04_source_contract_test.exs', 'integration/phase04_viewer_test.exs']
    else:
        focused = sorted(str(p.relative_to(app)) for directory in ['test', 'integration']
                         for p in (app / directory).rglob(f'*phase{args.phase:02d}*.exs'))
    required_focused = PHASE_REQUIRED_FOCUSED.get(args.phase, [])
    missing_focused = [name for name in required_focused if name not in focused]
    if missing_focused:
        raise RuntimeError(f'Missing required focused Phase {args.phase:02d} suites: {missing_focused}')
    if not focused:
        raise RuntimeError('Implement the selected phase focused suite before certification')
    if not list((app / 'browser/tests').glob(f'phase{args.phase:02d}*.spec.mjs')):
        raise RuntimeError('Implement the selected phase browser journeys before certification')
    run(['mix', 'test', *focused], app, {'MIX_ENV': 'test'})
    run(['mix', 'test', 'test', 'integration'], app, {'MIX_ENV': 'test'})
    if migrated:
        run(['mix', 'ecto.create', '-r', 'Fount.Repo'], app,
            {'MIX_ENV': 'test', 'FOUNT_DATABASE_URL': browser_url})
        run(['scripts/run_phase06_browser.sh'], overrides={'FOUNT_DATABASE_URL': browser_url,
            'FOUNT_ARTIFACT_ROOT': str(output / 'browser-artifacts'),
            'FOUNT_BROWSER_SERVER_LOG': str(output / 'browser-server.log')})
    for command in LADDER:
        run(command)
    for package in PACKAGES:
        directories = ['test'] if package == 'fount_observe' else ['test', 'integration']
        run(['mix', 'test', *directories], ROOT / 'packages' / package, {'MIX_ENV': 'test'})
    run(['mix', 'test', 'test', 'integration'], app, {'MIX_ENV': 'test'})
    for package in PACKAGES:
        run(['mix', 'hex.build'], ROOT / 'packages' / package, {'FOUNT_PACKAGE_BUILD': '1'})
    run(['mix', 'deps.get'], app, {'MIX_ENV': 'prod'})
    run(['mix', 'assets.deploy'], app, {'MIX_ENV': 'prod'})
    report['final_source'] = identity()
    report['passed'] = (report['source'] == report['final_source'] and migrated
                        and all(row['exit_code'] == 0 for row in report['results']))
    (output / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
