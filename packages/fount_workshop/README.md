<p align="center">
  <img src="assets/fount_workshop.svg" alt="Fount Workshop" width="200" height="200"/>
</p>

<p align="center">
  <a href="https://hex.pm/packages/fount_workshop"><img src="https://img.shields.io/hexpm/v/fount_workshop.svg" alt="Hex.pm"/></a>
  <a href="https://hexdocs.pm/fount_workshop"><img src="https://img.shields.io/badge/hex-docs-blue.svg" alt="HexDocs"/></a>
  <a href="https://github.com/nshkrdotcom/fount"><img src="https://img.shields.io/badge/GitHub-repo-black?logo=github" alt="GitHub"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License"/></a>
</p>

# Fount Workshop

**Writer revision workshop, agent collaboration loop, and PDF handoff engine for the Fount screenplay framework.**

Most AI writing tools fail working screenwriters. They overwrite text destructively, hallucinate away established scenes, disregard character voice, and provide no reliable undo or revision history. A professional writer cannot trust an assistant that treats an entire screenplay as an unconstrained chat prompt.

**Fount Workshop is built on the principle of absolute writer sovereignty.** Built on top of [Fount](https://hexdocs.pm/fount) and validated by [Fount Probe](https://hexdocs.pm/fount_probe), Fount Workshop provides an agentic revision loop where AI models propose structured changes, but the writer retains complete editorial authority:

* **Bounded Scene Revision Loop (`context → propose → preview → accept`):** AI agents operate on localized scene context and generate structured edit proposals.
* **Side-Effect-Free Myers Diffs:** Preview exact line additions, deletions, and structural changes in memory before any edit touches the database.
* **Historical Beat Recovery:** Surgically restore a cut dialogue line or action beat from 5 revisions ago into your current draft without rolling back intermediate progress.
* **Forensic PDF Export:** Professional screenplay PDF generation via pinned Afterwriting 1.17.3, paired with automated Poppler inspection (US Letter geometry, Courier Prime font embedding, zero blank pages).
* **Dated Submission Audits:** Mechanical pre-flight checks for major industry venues (Academy Nicholl Fellowship, The Black List) verifying title-page anonymity, page count budgets, and AI policy disclosures.
* **Dialogue Table Reads:** Extract ordered rehearsal sequences with character-mapped text-to-speech so you can hear your dialogue aloud.

---

## The Bounded Revision Workflow

Fount Workshop enforces a four-step revision cycle designed to eliminate accidental script corruption:

```text
┌────────────────────────────────────────────────────────────────────────┐
│  1. CONTEXT ISOLATION                                                  │
│  Extract target scene elements, surrounding narrative boundaries, and  │
│  stable element UUIDs. The AI never sees an unconstrained prompt.      │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│  2. STRUCTURED PROPOSAL                                                │
│  AI generates atomic operations (replace_text, insert, delete) bounded │
│  by a strict JSON schema. No freeform destructive rewrites.            │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│  3. IN-MEMORY PREVIEW & MYERS DIFFS                                    │
│  Compute source text diffs, element changes, and run Fount Probe       │
│  validation checks in pure memory. Zero database side effects.         │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│  4. WRITER ACCEPTANCE                                                  │
│  - ACCEPT: Changes commit atomically to PostgreSQL advancing revision. │
│  - REJECT: Drop preview—no database rows or revision hashes are moved. │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Core Capabilities

- **Writer-Controlled Collaboration:** Agents propose; writers decide. Every proposed revision is previewed as a clear red/green Myers diff against the current draft.
- **Historical Beat Recovery (`FountWorkshop.Recover`):** Screenwriters often cut a line or beat early in the writing process, only to realize later that it was crucial. Fount Workshop queries historical PostgreSQL revision trees, locates the exact element, and splices it cleanly into the current draft.
- **Competing Revision Alternatives:** Generate multiple distinct creative directions for a scene (e.g. subtext-heavy vs. direct confrontation) and review them side-by-side in formatted PDF packets before committing.
- **Automated PDF Inspection:** Renders production-standard screenplay PDFs and runs automated Poppler checks verifying 100% Courier Prime font embedding, proper page geometry (8.5 × 11 in), and no dangling blank pages.
- **Competition Pre-Flight Audits:** Screenplay competitions have strict submission rules. Fount Workshop audits your PDF against venue profiles (e.g. `:nicholl_2026_27`, `:black_list_2026`) checking for contact info violations on title pages, scene heading formatting, and AI content declarations.
- **Audio Table Reads:** Assign distinct TTS voices to characters, adjust playback pacing, and render ordered audio files for table-read rehearsals.

---

## Quickstart

### 1. Setup & Dependencies

Fount Workshop requires Poppler utilities for PDF inspection (`pdfinfo`, `pdffonts`, `pdftotext`) and Node.js for the pinned Afterwriting renderer:

```bash
# Ubuntu / Debian
sudo apt-get install -y poppler-utils

# macOS
brew install poppler

# Install Node dependencies in packages/fount_workshop:
npm ci
```

### 2. The Collaborative Revision Loop

Revise a scene with an AI model while maintaining complete veto power:

```elixir
alias FountWorkshop, as: Workshop

# 1. Load canonical screenplay from PostgreSQL
{:ok, script} = Fount.Persistence.load(Fount.Repo, "my-feature-slug")
scene = hd(script.ir.scenes)

# 2. Extract bounded scene context
{:ok, context} = Workshop.context(script, scene.id)

# 3. Request a revision proposal from an LLM
client = Inference.client!(
  adapter: Inference.Adapters.OpenAI,
  api_key: System.fetch_env!("OPENAI_API_KEY"),
  model: "gpt-4o"
)

{:ok, proposal} = Workshop.propose(
  context, 
  "Sharpen the dialogue subtext and heighten the physical tension", 
  client
)

# 4. Preview diffs in memory (zero database side effects)
{:ok, preview} = Workshop.preview(script, proposal)

# Inspect line-by-line text additions and deletions:
IO.puts(preview.source_diff)

# 5. Commit atomically only if the writer accepts:
:ok = Workshop.accept(Fount.Repo, "my-feature-slug", preview, script.revision.id)
```

If the writer rejects the proposal, simply discard `preview`. The database remains untouched.

### 3. Historical Beat Recovery

Restore a deleted beat from an earlier draft directly into your current working draft:

```elixir
# Restore a deleted beat by its historical element UUID
{:ok, result} = FountWorkshop.Recover.run(
  Fount.Repo, 
  "my-feature-slug", 
  original_revision_id, 
  cut_element_id
)

# The restored beat is packaged as a review packet with diffs:
{:ok, packet} = FountWorkshop.Review.packet(Fount.Repo, result.candidate.id)
IO.puts(packet["source_diff"])
```

### 4. PDF Export & Automated Inspection

Export a production-ready screenplay PDF with automated verification:

```elixir
{:ok, report} = FountWorkshop.Export.PDF.export(script, "priv/exports/feature.pdf")

report.pages          # => 104
report.page_size      # => :us_letter
report.courier_prime? # => true (verifies font embedding)
report.blank_pages    # => [] (asserts no accidental blank pages)
report.sha256         # => "f8a2..." (cryptographic proof of page layout)
```

### 5. Competition Submission Audits

Audit your screenplay against competition guidelines:

```elixir
alias FountWorkshop.Submission

{:ok, profile} = Submission.profile(:nicholl_2026_27)
check = Submission.check(script, report, profile)

check.status              # => :passed, :review_required, or :failed
check.mechanical_problems # => []
check.requires_writer_review
# => [:authorship_rights_and_current_rules, :verify_no_ai_generated_script_content]
```

### 6. Dialogue Table Reads

Hear your scene performed aloud by assigning voices to characters:

```elixir
alias FountWorkshop.TableRead

voices = %{
  sarah.id => "voice-sarah-lead",
  reese.id => "voice-reese-grit"
}

# Define your speech synthesis function (local eSpeak, ElevenLabs, or OpenAI Audio)
speech_fn = fn text, voice -> MyTTS.speak(text, voice: voice) end

# Synthesize audio clips turn-by-turn
{:ok, audio_turns} = TableRead.synthesize(script, scene.id, voices, speech_fn)
```

---

## Executable Live Examples

Fount Workshop includes live scripts demonstrating historical beat recovery, competing creative alternatives, multi-scene restructuring, and PDF exports:

```bash
export FOUNT_DATABASE_URL="ecto://postgres:postgres@localhost:5432/fount_dev"
export SYSTEM_ONE_API_KEY="your-typesafe-api-key"
export FOUNT_CODEX_MODEL="gpt-4o"

# Restore a historical beat and render PDF diff review packet:
mix run examples/live.exs --mode recover --out examples/_output/recover

# Generate 3 competing creative directions for a scene:
mix run examples/live.exs --mode alternatives --out examples/_output/alternatives

# Restructure an entire sequence across multiple scenes:
mix run examples/live.exs --mode sequence_routes --out examples/_output/sequence_routes

# Run full revision pass with atomic acceptance demo:
mix run examples/live.exs --mode recover --accept_demo --out examples/_output/accepted_demo
```

Consult the [**Workshop Examples Guide**](examples/README.md) for full instructions, prerequisites, and output manifests.

---

## Comprehensive Guides

Explore detailed guides covering Fount Workshop's systems:

* [**Workshop Architecture**](guides/architecture.md) — The poncho structure, separation of concerns, and revision lifecycles.
* [**Scene Revision Loop**](guides/scene-revision-loop.md) — The 4-step workflow, proposal schemas, and atomic acceptance.
* [**Proposals & Myers Diffs**](guides/proposals-and-diffs.md) — Structured operations, change sets, and visual text diffing.
* [**PDF Export & Inspection**](guides/pdf-export-and-inspection.md) — Afterwriting integration, Poppler checks, and revision hashing.
* [**Submission Compliance**](guides/submission-checks.md) — Nicholl and Black List profiles, mechanical criteria, and AI policy flags.
* [**Dialogue Table Reads**](guides/table-reads-and-audio.md) — Turn extraction, voice routing, and pluggable speech synthesis.
* [**Live Examples**](examples/README.md) — Executable revision, recovery, and PDF publication scripts.

---

## The Fount Ecosystem

Fount Workshop is the top-tier creative application layer of the Fount screenplay framework:

1. **[Fount](https://hexdocs.pm/fount)**: The headless screenplay engine, lossless CST parser, and relational revision store.
2. **[Fount Probe](https://hexdocs.pm/fount_probe)**: The dramaturgical auditor and diagnostic engine. 100% read-only inspection for character knowledge, continuity, scene mechanics, and voice attribution.
3. **[Fount Workshop](https://hexdocs.pm/fount_workshop)**: The writer's studio. Bounded AI revision loops with Myers diffs, beat recovery, competition submission checks, and PDF publishing.

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
