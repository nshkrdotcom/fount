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

Fount Workshop is the application layer built on top of [Fount](https://hexdocs.pm/fount). It provides the workflows writers and AI agents need to draft, iterate, inspect, and rehearse screenplays:

* **Bounded Scene Revision Loop:** An agentic workflow (`context → propose → preview → accept`) where the writer retains full editorial authority.
* **Side-Effect-Free Previews:** Review Myers text diffs and structural changes before any edit touches the database.
* **Forensic PDF Export:** Professional screenplay PDF generation via pinned Afterwriting 1.17.3, paired with automated Poppler inspection (US Letter geometry, Courier Prime font embedding, blank page checks).
* **Dated Submission Audits:** Mechanical checks for competition and evaluation profiles (e.g. The Black List, Academy Nicholl Fellowship) with explicit AI policy and title-page anonymity flags.
* **Dialogue Table Reads:** Extraction of ordered rehearsal sequences with pluggable TTS voice mapping.

---

## Quickstart

### 1. Setup & Installation

Ensure you have Poppler utilities installed on your system (`pdfinfo`, `pdffonts`, `pdftotext`). Then install the dependencies and the pinned renderer:

```bash
cd packages/fount_workshop
mix deps.get
npm ci
```

### 2. Revise a Scene with AI

Extract a bounded scene context, generate structured proposals with an `Inference` client, preview diffs in memory, and commit atomically:

```elixir
alias FountWorkshop, as: Workshop

# 1. Load canonical screenplay from PostgreSQL
{:ok, script} = Fount.Persistence.load(Fount.Repo, "my-feature")
scene = hd(script.ir.scenes)

# 2. Extract scene context and stable element IDs
{:ok, context} = Workshop.context(script, scene.id)

# 3. Request a revision from an LLM
client = Inference.client!(
  adapter: Inference.Adapters.OpenAI, 
  api_key: System.fetch_env!("OPENAI_API_KEY"), 
  model: "gpt-4o"
)
{:ok, proposal} = Workshop.propose(context, "Sharpen the dialogue and heighten tension", client)

# 4. Preview diffs in memory (zero database side effects)
{:ok, preview} = Workshop.preview(script, proposal)
preview.source_diff   # Inspect text additions/deletions
preview.semantic_diff # Inspect element-level changes

# 5. Accept changes atomically against the base revision
:ok = Workshop.accept(Fount.Repo, "my-feature", preview, script.revision.id)
```

If the writer rejects the proposal, simply drop the preview—no database rows are modified.

### 3. PDF Export and Inspection

Generate industry-standard screenplay PDFs and receive an automated inspection report:

```elixir
{:ok, report} = FountWorkshop.Export.PDF.export(script, "priv/exports/feature.pdf")

report.pages          # => 102
report.page_size      # => :us_letter
report.courier_prime? # => true
report.blank_pages    # => []
report.sha256         # => "a4b2..."
```

### 4. Audit Submission Compliance

Audit a rendered PDF against dated venue profiles before submitting:

```elixir
alias FountWorkshop.Submission

{:ok, profile} = Submission.profile(:nicholl_2026_27)
check = Submission.check(script, report, profile)

check.status              # => :failed or :review_required
check.mechanical_problems # => []
check.requires_writer_review
# => [:authorship_rights_and_current_rules, :verify_no_ai_generated_script_content]
```

### 5. Dialogue Table Reads

Hear scenes aloud by routing ordered dialogue turns through a voice map and speech engine:

```elixir
alias FountWorkshop.TableRead

# Map voices to characters
voices = %{
  sarah.id => "voice-sarah-lead",
  "REESE" => "voice-reese"
}

# Define your TTS synthesis function
speech_fn = fn text, voice -> MyTTS.speak(text, voice: voice) end

# Synthesize rehearsal audio clips
{:ok, audio_turns} = TableRead.synthesize(script, scene.id, voices, speech_fn)
```

---

## Documentation Guides

Explore comprehensive guides on Fount Workshop's systems:

* [**Workshop Architecture**](guides/architecture.md) — Poncho layout, separation from core Fount, and revision lifecycle.
* [**Scene Revision Loop**](guides/scene-revision-loop.md) — The 4-step workflow, mock testing, and atomic acceptance.
* [**Proposals & Diffs**](guides/proposals-and-diffs.md) — JSON Schema enforcement, bounded operations, and Myers diffing.
* [**PDF Export & Inspection**](guides/pdf-export-and-inspection.md) — Afterwriting layout engine, Poppler forensic checks, and revision hashing.
* [**Submission Checks**](guides/submission-checks.md) — Black List and Nicholl profiles, mechanical criteria, and AI policy flags.
* [**Dialogue Table Reads**](guides/table-reads-and-audio.md) — Turn extraction, voice routing, and pluggable speech synthesis.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
