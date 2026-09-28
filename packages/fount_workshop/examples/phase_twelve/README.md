# Phase 12 provider-free writer path

This is a runnable persistence/CLI example for the Phase-12 discovery contract. It uses no Inference, Observe, System One, ASM, speech or PDF provider. PostgreSQL is still required because these are durable writer sessions and real candidates, not an in-memory demo store.

From `packages/fount_workshop`, with Fount migrations already applied:

```bash
export FOUNT_DATABASE_URL='ecto://postgres:postgres@localhost:5432/fount_dev'
OUT=examples/_output/phase_twelve
rm -rf "$OUT"

mix fount.open --new --key phase12-pool \
  --request examples/phase_twelve/open_request.json --output "$OUT"
SESSION_ID=$(python3 -c 'import json; print(json.load(open("examples/_output/phase_twelve/session.json"))["id"])')
BASE_REVISION=$(python3 -c 'import json; print(json.load(open("examples/_output/phase_twelve/session.json"))["base_revision_id"])')

mix fount.fragment --session "$SESSION_ID" \
  --request examples/phase_twelve/image_fragment.json --output "$OUT"
FRAGMENT_ID=$(python3 -c 'import json; print(json.load(open("examples/_output/phase_twelve/fragment.json"))["id"])')
mix fount.brief --session "$SESSION_ID" \
  --request examples/phase_twelve/brief_patch.json --output "$OUT"

mix fount.manual --session "$SESSION_ID" --actor phase12-writer \
  --request examples/phase_twelve/manual_candidate.json --output "$OUT/review-1"
CANDIDATE_ID=$(python3 -c 'import json; print(json.load(open("examples/_output/phase_twelve/review-1/candidate.json"))["candidate_id"])')

python3 - "$FRAGMENT_ID" "$CANDIDATE_ID" > "$OUT/adopt.json" <<'PY'
import json, sys
print(json.dumps({"action": "adopt", "fragment_id": sys.argv[1], "candidate_id": sys.argv[2]}))
PY
mix fount.fragment --session "$SESSION_ID" \
  --request "$OUT/adopt.json" --output "$OUT"

mix fount.edit --candidate "$CANDIDATE_ID" --actor phase12-writer \
  --request examples/phase_twelve/manual_edit.json --output "$OUT/review-2"
EDITED_ID=$(python3 -c 'import json; print(json.load(open("examples/_output/phase_twelve/review-2/candidate.json"))["candidate_id"])')

# Review the actual candidate pages/diff before this explicit decision.
mix fount.accept --candidate "$EDITED_ID" \
  --expected-revision "$BASE_REVISION" --actor phase12-writer

# Switch is explicit; the immutable opening request remains in provenance.
mix fount.mode --session "$SESSION_ID" \
  --request examples/phase_twelve/inspect_mode.json --output "$OUT"
mix fount.session --id "$SESSION_ID" --output "$OUT/resumed"
```

The accepted draft, candidate history, pending question, protected material and mode history remain separately visible in the session/review artifacts. `fount.manual` and `fount.edit` compile writer-origin typed operations through the same candidate/review/acceptance path used for generated pages.

For deterministic generated alternatives, run the Phase-12 fixture test:

```bash
mix test test/writer_workflows/phase_twelve_scene_exploration_test.exs
```

Its scripted Inference adapter requests three treatment routes—revelation/concealment, relationship/voluntary disclosure, and action/accidental exposure—materializes actual candidate pages, exercises `keep_both` and `reject_all`, and rejects a mock that returns three confession paraphrases. The fixture is deterministic; it is not a claim about live-model quality.
