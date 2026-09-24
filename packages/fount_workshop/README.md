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

Fount Workshop is a writer-controlled app layer over [Fount](https://hexdocs.pm/fount)'s canonical screenplay model. It adds model proposals, preview/accept, PDF export and dated submission checks. Fountain and FDX remain import/export formats. This is a separate Mix project in the poncho, with no web server or background process.

## Setup

Use Elixir 1.18 or later, PostgreSQL for accepted canonical revisions, Node.js 22 or later, and Poppler's `pdfinfo`, `pdffonts`, and `pdftotext` commands. Configure/start `Fount.Repo` and run `Ecto.Migrator.run(Fount.Repo, Fount.Persistence.migrations_path(), :up, all: true)` before using the relational workflow. From this directory:

```bash
mix deps.get
npm ci
mix test
```

`npm ci` installs the pinned Afterwriting 1.17.3 renderer. Model calls are opt-in. Offline tests use `Inference.Adapters.Mock`; a live provider is configured through an `Inference.Client` at the application edge. No model credentials are needed for PDF export or tests.

## Revise a scene

The loop is `context → propose → preview → accept`. For a canonical screenplay, `context/3` includes selected scene text and stable element IDs. The proposal decoder accepts bounded `replace_text` operations for action, dialogue or parentheticals and `set_scene_heading` for the selected scene. Preview runs through pure `Fount.Screenplay.apply/2`; accept commits through `Fount.Persistence.save/4` against the base revision.

```elixir
alias FountWorkshop, as: Workshop

{:ok, script} = Fount.Persistence.load(Fount.Repo, "feature")
scene = hd(script.ir.scenes)
{:ok, context} = Workshop.context(script, scene.id)

# Configure this client with an Inference adapter/provider available to you.
client = Inference.client!(adapter: MyAdapter, provider: :my_provider, model: "my-model")
{:ok, proposal} = Workshop.propose(context, "Tighten the dialogue", client)
{:ok, preview} = Workshop.preview(script, proposal)

preview.source_diff
preview.semantic_diff

# Reject by discarding the preview; no database row has changed.
# Accept after review, against the revision used to build the context:
:ok = Workshop.accept(Fount.Repo, "feature", preview, script.revision.id)
```

`accept/5` compares the current relational revision and saves model, typed rows and acceptance provenance in one transaction. The earlier `Fount.Document`/filesystem workflow remains available as a compatibility path; it writes a separate acceptance record under `.fount_workshop/acceptances`. Do not infer that an unrecorded draft contains no AI content.

## Export and check a submission artifact

```elixir
{:ok, script} = Fount.Persistence.load(Fount.Repo, "feature")
{:ok, pdf} = FountWorkshop.Export.PDF.export(script, "out/feature.pdf")
{:ok, profile} = FountWorkshop.Submission.profile(:black_list)
check = FountWorkshop.Submission.check(script, pdf, profile)
```

The PDF report contains page count, detected paper size and Courier Prime embedding, file hash, and model revision. The exporter uses US Letter and suppresses notes and scene numbers. Review the PDF visually before sending it. The renderer is a presentation adapter.

## Rehearse dialogue

`Fount.Writer.table_read/3` returns ordered turns with literal cues, linked cast IDs, dialogue, parentheticals and dual-dialogue metadata. `FountWorkshop.TableRead.synthesize/4` routes those turns through a caller-supplied speech function and a voice map keyed by cast ID or cue. It returns ordered audio clips for playback; it reports missing voice mappings and speech failures explicitly. The workshop does not bundle a voice engine.

Profiles are dated mechanical checks, not eligibility certificates. `:black_list` checks the PDF without inventing a universal page range. `:nicholl_2026_27` checks its current 80–125 page range and title-page anonymity, and flags accepted AI-generated screenplay text against its published rule. Both leave rights, authorship, and current-rule verification to the writer. See the [Black List help center](https://help.blcklst.com/kb/guide/en/writers-pROPvK6l0J/Steps/2724678) and [Academy 2026–27 Nicholl rules](https://www.oscars.org/sites/oscars/files/2026-06/2026-2027%20Nicholl%20Rules%20Terms%20and%20Conditions%20%281%29.pdf).

## Quality checks

```bash
mix format --check-formatted
mix deps.unlock --check-unused
mix compile --warnings-as-errors
mix test
mix credo --strict
mix dialyzer
mix docs --warnings-as-errors
```

The core package has its own independent gate. The workshop is an app project and is not published to Hex.
