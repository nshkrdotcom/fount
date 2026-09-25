# Local application and environment

## Repositories

The receiving filesystem paths are exactly:

```text
~/p/g/n/fount
~/p/g/n/system_one_sdk
~/p/g/n/inference
```

Work in Fount only. System One is the sibling source dependency at `../../../system_one_sdk/packages/system_one_sdk` relative to the Probe package. Inference and Agent Session Manager remain ordinary **Hex** dependencies (`~> 0.4.0` and `~> 0.16.0` in this source). The supplied earlier run resolved Inference 0.4.1 and Agent Session Manager 0.16.0; no new resolution occurred here. The reference Inference checkout is for inspecting the supplied APIs, not a replacement local-path dependency. No lockfiles were supplied as reconstructible Fount files and none were fabricated.

Use the local Elixir 1.20/OTP29 environment previously used by the project, then inspect `elixir --version` and `mix --version`. Probe's source declares `~> 1.19`; align the consuming package's lower bound when verifying. Do not install or switch toolchains blindly on behalf of the writer.

## Apply safely

Keep the delivered ZIP, external manifest and installer together in a chosen directory. The following uses `~/Downloads/fount-continuation` as an explicit example destination. It does not reset Git or touch a database.

```bash
cd ~/p/g/n/fount
git status --short
git diff --stat
git diff -- packages/fount packages/fount_probe packages/fount_workshop docs/implementation_handoff

DELIVERY="$HOME/Downloads/fount-continuation"
python3 "$DELIVERY/apply_overlay.py" \
  --root "$HOME/p/g/n/fount" \
  --archive "$DELIVERY/fount-overlay.zip" \
  --manifest "$DELIVERY/fount-overlay.manifest.json" \
  --dry-run
```

The XML body omits the delimiter newline before `</file>`, so its reconstructed preimage may differ from a normal checkout by one final LF. If that is the **only** mismatch and the manifest's alternative matches the inspected checkout, rerun dry-run with `--allow-terminal-newline`. This option accepts only the separately computed body-plus-one-LF hash. It does not ignore spaces, CRLF changes, arbitrary content, hashes or local edits. There is deliberately no `--force` and no Git hash guard.

After all touched files are reviewed, use the same command with `--apply` rather than `--dry-run`, and add the LF option only if required and reviewed. The installer stages payloads, rechecks touched preimages, preserves originals and modes under `.fount-overlay-backups/<transaction>/`, writes a journal, and applies explicit deletions last. This overlay's deletion list is empty. Keep backups until verification is complete. Do not manually extract over local modifications to avoid a collision refusal.

The manifest is archive metadata under `handoff/fount-overlay.manifest.json` and externally beside the ZIP. Per the original contract, it does not hash or install itself. A previous tracked manifest can remain in the checkout as historical metadata; it is not the manifest for this delivery. Every other archive member is an individually hashed payload in the new manifest.

## Offline package setup and checks

```bash
cd ~/p/g/n/fount
bash scripts/verify_handoff.sh --offline
```

The script executes each package's dependency retrieval, format check, test compilation with warnings as errors and default tests with `SYSTEM_ONE_API_KEY`, `FOUNT_DATABASE_URL`, `FOUNT_CODEX_MODEL` unset. It writes separate local logs and a TSV status record. Dependency retrieval is network setup, not a live model call. Default `mix test` must not require a database, provider, renderer or speech process. Fix source, format and test failures, then rerun the same commands. Do not call formatting unrun source "green".

## Explicit fresh PostgreSQL database

Choose a new database yourself. Never point initial validation at an existing writer database or execute a drop/reset command. Set an explicit connection URL using your local secret mechanism; do not copy passwords into reports. The local WSL port may be 5433, but confirm rather than silently assume it.

```bash
# Set FOUNT_DATABASE_URL to the explicitly selected fresh database first.
cd ~/p/g/n/fount/packages/fount
MIX_ENV=test mix run -e '
  url = System.fetch_env!("FOUNT_DATABASE_URL")
  case Fount.Repo.__adapter__().storage_up(url: url) do
    :ok -> :ok
    {:error, :already_up} -> :ok
    error -> raise inspect(error)
  end
  {:ok, _} = Fount.Repo.start_link(url: url, pool_size: 5)
  Ecto.Migrator.run(Fount.Repo, Fount.Persistence.migrations_path(), :up, all: true)
'
```

The adapter `storage_up` call and migration command are proposed local instructions, not commands verified in this pass. Confirm the current Ecto API during the first compile. The existing database being present is not permission to reset it. Then run Core `MIX_ENV=test mix test integration` and Workshop integration tests, which make real DB/PDF calls. Integration tests are not part of the offline default.

## PDF prerequisites

Workshop pins Afterwriting `1.17.3` in `package.json`. From `packages/fount_workshop`, run `npm install` locally and inspect the produced lockfile; there is no fabricated `package-lock.json`, so do not assume `npm ci` is usable first. Install/confirm Node and actual `pdfinfo`, `pdftotext`, `pdffonts` from Poppler using your system's normal process. The source locates the Afterwriting CLI from the owning Workshop package. Confirm runtime paths locally. No generated PDFs are included as supposed evidence from this pass.

## Codex and Jev

Use valid local Codex/Agent Session Manager authentication and set `FOUNT_CODEX_MODEL` to the approved installed Codex model. Set `SYSTEM_ONE_API_KEY` for Jev. The source uses the supplied public Inference ASM completion boundary and System One SDK; it does not silently switch providers. The user-specific `/home/home/scripts/with_bash_secrets` wrapper may be used only if it exists. Never print its environment or embed credentials in logs, source, the ZIP or reports.

Library clients may use explicit endpoint/key configuration supported by the supplied SDK. The simple launcher currently uses its normal default endpoint; custom endpoint selection should use caller-supplied clients instead of changing provider internals.

## Optional speech

Install `espeak-ng` or `espeak` only if speech is desired. Set `FOUNT_VOICES_FILE` to an existing JSON file mapping a confirmed character ID or cue name to an installed voice, for example `{"MARA":"en-us","DAN":"en-gb"}`. This is configuration, not a generated audio claim. `mix fount.read --key KEY --output DIRECTORY --speech` makes real synthesis calls and fails when a voice/executable is missing. No fallback waveform is fabricated.
