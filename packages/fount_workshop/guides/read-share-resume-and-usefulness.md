# Read, share, resume, and usefulness evidence

Phase 15 closes the writer loop without turning Fount into a screenplay grader. The accepted canonical screenplay remains the source of truth; read packets, clean shares, comparisons, and usefulness records are projections or evidence around that source.

## Human table-read packet

`FountWorkshop.TableRead.packet/3` is provider-free. It records:

- exact source screenplay and revision identity;
- the explicit selection and its canonical hash;
- scene context and literal roles/cues;
- exact selected performed material;
- ordered dialogue turns, including dual-dialogue relationships;
- caller-supplied human reactions.

Speech is optional. `FountWorkshop.TableRead.record_reaction/2` accepts only a human observer and keeps the reaction, script wording, reader delivery, and listening conditions in separate fields. Synthesized speech can deliver lines, but Fount does not convert TTS output or generated transcripts into measured laughter, suspense, attention, timing, or actor endorsement.

`mix fount.read --key SCRIPT --output OUT` still writes `table-read.json` and `table-read.html`. Phase 15 additionally writes:

- `table-read.packet.json` — provider-free human-read packet;
- `share/screenplay.fountain` — clean accepted-draft reader copy;
- `share/screenplay.fdx` — clean FDX reader copy;
- `share/share.manifest.json` — selection, privacy exclusions, hashes, and fidelity losses.

`--speech` remains an optional convenience and is not required for the packet or share.

## Clean reader share

`FountWorkshop.Share.export/4` accepts the whole screenplay or complete scene targets. Fine-grained spans are rejected rather than silently expanded into a larger share.

The reader projection excludes private notes, boneyards, omitted scenes, section/synopsis development structure, Workshop candidates, rejected alternatives, provider metadata, analysis packets, and other session state. It retains title metadata and supported screenplay content. FDX adapter losses such as a page break that cannot be represented are reported in `unsupported_or_lossy`; they are never silently treated as fidelity.

The clean share is a projection. It does not mutate the canonical revision or mark any candidate accepted.

## One provider-free end-to-end path

The same existing CLI commands can carry a scene session from capture through resume. No graphical editor and no provider credentials are required for this human-only path.

```bash
# 1. Open a writer-controlled session from an existing canonical screenplay.
mix fount.open --key SCRIPT --request open_request.json --output out/open

# 2. Capture a fragment/image/note without changing canon.
mix fount.fragment --session SESSION_ID --request fragment.json --output out/capture

# 3. Move explicitly into Explore when wanted.
mix fount.mode --session SESSION_ID --request explore_mode.json --output out/explore

# 4. Create a writer-origin revision candidate from typed operations.
mix fount.manual --session SESSION_ID --request manual_candidate.json --output out/revise --actor writer

# 5. Revise that candidate. Candidate outputs include the existing review/comparison packet.
mix fount.edit --candidate CANDIDATE_ID --request manual_edit.json --output out/compare --actor writer

# 6. Decide explicitly. Acceptance advances canon; rejection does not.
mix fount.accept --candidate CANDIDATE_ID --expected-revision BASE_REVISION_ID --actor writer --principal-type human --approval-id STABLE_APPROVAL_UUID
# or:
mix fount.reject --candidate CANDIDATE_ID --actor writer

# 7. Read and share only the accepted canonical draft.
mix fount.read --key SCRIPT --output out/read

# 8. Resume the saved session without provider dispatch.
mix fount.session --id SESSION_ID --output out/resume
```

The accepted revision ID remains the source identity for the human-read packet and clean share. Stale siblings still require reconciliation and cannot overwrite a newer accepted/manual head. Retrying the same explicit acceptance remains idempotent through the existing persistence boundary.

## Three evaluation conditions

Phase 15 preserves three separately runnable conditions for future comparative work. It does not assume a winner.

### Human-only

Use the provider-free path above: capture, manual candidate/edit, review, explicit accept/reject, read/share, resume.

### Basic unstructured LLM help

A host can call the provider-neutral Inference facade directly, outside Fount's structured revision workflow, then record the returned text as the baseline output:

```elixir
client = Inference.client!(adapter: MyConfiguredAdapter, model: "host-selected-model")
{:ok, response} = Inference.complete(client, prompt)
text = Inference.Response.text(response)
```

The host owns adapter configuration and credentials. This baseline does not gain Fount provenance, typed edit, comparison, acceptance, or consequence semantics merely because the text was produced by an LLM.

### Fount-assisted

Use the existing `mix fount.write`, strategy/materialization, review/comparison, and explicit acceptance paths. Resource preflight and partial/resume behavior remain governed by the existing Session implementation.

## Usefulness evidence without a screenplay score

`FountWorkshop.Usefulness.record/1` keeps engineering observations separate from human response. The human response can record:

- task completion;
- time to a useful next decision;
- writer agency;
- voice retention;
- alternative diversity;
- consequence usefulness;
- time spent rejecting irrelevant material;
- friction, preference, and whether the writer kept the original.

`FountWorkshop.Usefulness.report/2` preserves positive, neutral, and negative records. Keeping the original can be a successful outcome. The report does not calculate an aggregate screenplay score, pick a winning condition, turn acceptance rate into quality, fabricate expert endorsement, or claim a small sample is representative.

The deterministic Phase-15 tests exercise the record shape only. The optional four-writer comparative study in D046 is **NOT_RUN** until commissioned and performed with real writers; no human result is inferred from test fixtures.