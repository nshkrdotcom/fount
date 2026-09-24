# Local setup

Repositories:

```text
~/p/g/n/fount
~/p/g/n/system_one_sdk
~/p/g/n/inference
```

Use Elixir 1.19 or a compatible later version. The supplied dependency checkouts
are authoritative. System One is consumed at `packages/system_one_sdk`, with its
sibling `system_one_contracts` package intact. Inference is consumed at
`apps/inference`.

## Apply the source overlay

Place `fount-overlay.zip`, `fount-overlay.manifest.json` and the extracted
`apply_overlay.py` together. Inspect local work first:

```bash
cd ~/p/g/n/fount
git status --short
git diff --stat
python3 /path/to/apply_overlay.py \
  --root "$HOME/p/g/n/fount" \
  --archive /path/to/fount-overlay.zip \
  --manifest /path/to/fount-overlay.manifest.json \
  --dry-run
```

Resolve reported touched-file conflicts by reviewing the complete old/local/new
contents. Do not force-reset or discard unrelated work. Once the preflight is
clean, rerun with `--apply` instead of `--dry-run`. Keep the transaction backup
until the local implementation and tests have been reviewed.

A Repomix export can normalize original bytes. Preimage differences are genuine
manual-review conditions, not permission to bypass the installer.

## Dependencies and offline checks

First audit retained app/test startup so it cannot launch PostgreSQL, renderers,
speech or authenticated providers by default. Then:

```bash
for package in fount fount_probe fount_workshop; do
  (
    cd "$HOME/p/g/n/fount/packages/$package"
    mix deps.get
    mix format --check-formatted
    MIX_ENV=test mix compile --warnings-as-errors
    env -u SYSTEM_ONE_API_KEY -u FOUNT_DATABASE_URL -u FOUNT_CODEX_MODEL \
      MIX_ENV=test mix test
  )
done
```

These commands are instructions for the local agent, not reported successful
runs. Resolve dependency conflicts in Fount only; do not edit SDK internals.

## Fresh PostgreSQL schema

**Implement and review the fresh-schema migration first.** The reference SQL
travels with the specification; the delivery does not claim the migration is
complete. Do not run a destructive reset against an existing database.

Choose an unused database name and an explicit connection URL. `createdb` should
fail if the chosen database already exists; do not respond by dropping it.
After completing the migration, run the project's Ecto create/migrate commands
against that dedicated database and run the explicit integration suite.

Never put a password-bearing database URL into committed files, run manifests or
handoff logs. Configure `FOUNT_DATABASE_URL` in the host environment.

## Generative and semantic providers

Launchers read `SYSTEM_ONE_API_KEY`, optional `SYSTEM_ONE_BASE_URL`,
`FOUNT_JEV_MODEL` (default `jev-latest`), and explicit `FOUNT_CODEX_MODEL`.
All generation goes through Inference with its Codex ASM adapter in an empty
completion working directory. `agent_session_manager ~> 0.16.0` is a development
runtime dependency, not a fourth source input. Do not call its session API from
Fount or add a second CLI wrapper.

## Output tools

Complete the existing Afterwriting 1.17.3 integration with runtime path
resolution. Install its existing lockfile-defined dependencies locally. Real
verification uses `pdfinfo`, `pdftotext -layout` and `pdffonts`, plus visual PDF
inspection. Optional speech uses real `espeak-ng` WAV generation. No word count
may be substituted for a measured page count.
