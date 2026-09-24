# PostgreSQL model and transactions

## Chosen representation

Replace the current head-only relational projection plus historical JSON snapshot arrangement with immutable relational screenplay rows for every revision. Current, historical and candidate revisions use the same loader and queries. Stable scene/element/character IDs recur across revisions; their row identity includes the revision. Full copies are appropriate for feature screenplay sizes and keep historical querying, candidate comparison and recovery straightforward.

The reference [schema.sql](contracts/schema.sql) specifies columns, keys and essential constraints. Translate it to Fount-owned Ecto migrations and schemas. It is a fresh schema specification, not a migration to run over existing tables. The repo is greenfield: replace the old migration chain and document a fresh development database setup. Never have setup commands automatically drop an existing database. Preserve imported files independently; no legacy data conversion is required for this release.

PostgreSQL supports composite keys and foreign keys for this representation; Ecto transactions can group the application operations. [PostgreSQL constraints](https://www.postgresql.org/docs/current/ddl-constraints.html), [Ecto.Multi](https://ecto.hexdocs.pm/Ecto.Multi.html).

## Stored objects

| Tables | Meaning and ownership |
| --- | --- |
| `screenplays` | Project key and accepted head revision; no model-generated summary is canonical here. |
| `revisions` | Immutable revision metadata, parent, content hash, import artifact reference. Candidates and accepted drafts use the same table. |
| `title_entries`, `scenes`, `dialogue_blocks`, `elements` | Complete ordered literal screenplay representation for one revision. |
| `characters`, `character_aliases`, `mentions`, `mention_candidates` | Authored cast and explicit links plus stored mention status. A mention does not prove attendance. |
| `authored_items` | Writer brief, story plan, note, constraint, fact declaration, voice direction, sequence/storyline membership and perspective access declarations. JSON values preserve each domain shape. |
| `import_artifacts` | Original bytes, format, checksum, render hash and fidelity information. |
| `writing_sessions` | One creative request, base revision, brief, strategies, progress and model metadata. Mutable working record; it does not advance the draft. |
| `writing_candidates` | Session candidate, parent candidate if iterated, base and result revisions, typed change groups, strategy and provenance. Immutable payload; decision status is separate. |
| `analysis_reports`, `analysis_report_sources` | Immutable reports and the exact revisions used as evidence. Derived annotations/graphs are report JSON, never canonical screenplay rows. |
| `acceptances` | Accepted base/result revisions, candidate when applicable, writer actor, operations and origin provenance. |

A new project can have an empty screenplay revision containing only an authored brief. Beat plans belong in authored items when adopted, and in the writing session while exploratory. They can exist without scene rows. This is required for W01.

Do not normalize every Jev answer into a separate table. Report payloads contain judgments, probabilities, input manifests, provenance and findings; their relational access needs are screenplay, revision, tool, session and creation time. Do not add generic entity/property/value tables or persistent tables for every craft category.

## IDs, ordering and hashes

All canonical IDs are UUID strings. Revision IDs are new UUIDs, not hashes. The same element UUID can appear in multiple revisions of the same screenplay. Use `(screenplay_id, revision_id, id)` for structural row keys and corresponding foreign keys.

Ordinals are zero-based integers, unique within their table and revision. Element order is the canonical reading order. Scene order matches heading order. A dialogue block's order matches its cue. Pre-scene elements can have a null `scene_id`. Empty scenes are valid; orphan dialogue is not.

`content_hash` is SHA-256 over the canonical JSON encoding of authored content: stable IDs, ordered IR, cast, confirmed/authored mention decisions and authored items. Sort object keys lexicographically; sort unordered keyed collections by ID; retain semantic array order. Exclude the top-level revision metadata, indexes, derived reports, original byte blobs, source spans/references and generated provenance fields. Authored item status and writer wording remain included; resolution audit fields (accepted revision/group IDs) are excluded. Cast and mention identity/decisions remain included. Serialize finite numbers consistently through one canonical encoder.

`render_hash` covers the canonical export-relevant IR and title data, including markup, omissions and ordering, excluding authored metadata and UUID identity. An imported artifact stores its initial render hash. Reuse original bytes only when the current render hash matches and the export mode/format requests archival fidelity. Thus adding a writer note in metadata need not destroy exact imported Fountain export. Spec export applies its own presentation settings and may intentionally produce different bytes.

The canonical codec retains raw lexical content and inline marks needed to preserve emphasis on regenerated output. Any changed element clears or recomputes obsolete lexical fields. Never allow stale `raw_text` to override edited `text`.

## Integrity rules beyond SQL

Validate these in pure core code before persistence:

- Heading/cue ownership matches the referenced scene/block. A dialogue block's body and cue are contiguous under the supported Fountain grammar; blocks do not span scenes.
- Dual dialogue links are reciprocal, adjacent, in one scene, and have left/right sides. Neither a partial deletion nor a split can leave a dangling partner.
- Every element appears once in canonical order. Scene/block membership arrays and derived indexes agree with row foreign keys.
- Mention spans are UTF-8 byte ranges within current element text and match their stored surface. Confirmed mentions require a chosen character; ambiguous mentions have candidates but no chosen character. Suggested links retain their producer and cannot be treated as confirmed by query defaults.
- Typed authored targets and dependencies resolve in the same revision unless status is `unresolved`. A deletion preserves the authored item with its missing target recorded; it never silently retargets it.
- A parent revision exists in the same screenplay and is the actual base of the edits. Persistence must not rewrite a supplied parent to the current head to conceal a stale proposal.
- A stored report's evidence targets are checked against its listed source revisions. A generated explanatory citation must be a member of the report's evidence registry.
- A candidate's result revision has its declared base as parent. Combining partial changes produces a new candidate from a chosen base, not a second parent tree.

Database checks cover row identity, scope, foreign keys, uniqueness, basic value domains and confidence ranges. Pure validators cover screenplay relationships and typed JSON targets. Do not build a general proof system or trigger interpreter.

## Transaction APIs

All APIs accept a caller-owned Ecto repo module. Core owns schemas and SQL; Workshop owns creative content. Signatures are normative; existing API names may delegate while callers migrate.

```elixir
Fount.Persistence.create(repo, key, root_model, opts)
# {:ok, screenplay}; root parent must be nil; duplicate key -> :key_taken
Fount.Persistence.load(repo, key)
Fount.Persistence.load_revision(repo, screenplay_id, revision_id)
Fount.Persistence.history(repo, screenplay_id, head: revision_id, limit: 50, before: cursor)
Fount.Persistence.save_edit(repo, key, candidate, expected_revision: base_id,
  operations: ops, actor: actor, origin: :writer_edit)
Fount.Persistence.save_session(repo, session)
Fount.Persistence.save_candidate(repo, session_id, candidate)
Fount.Persistence.save_report(repo, report, opts \\ [])
Fount.Persistence.accept_candidate(repo, candidate_id, expected_revision: base_id,
  actor: actor, review: review_decision)
Fount.Persistence.reject_candidate(repo, candidate_id, actor: actor)
```

Return `{:ok, value}` or `{:error, reason}` consistently. Known errors include `:not_found`, `:key_taken`, `{:stale_revision, actual}`, `:wrong_screenplay`, `:invalid_model`, `:unresolved_conflicts`, `:missing_review`, and `:already_rejected`. Constraint violations become domain errors; unexpected database failures retain a sanitized cause.

**Create:** validate root; insert screenplay with null head, artifact if supplied, revision and all rows; insert an import/writer acceptance event if applicable; set head; commit. New project uniqueness races return `:key_taken`.

**Save an ordinary edit:** lock screenplay `FOR UPDATE`, compare expected head, validate parent and candidate, insert revision/rows, insert acceptance with `writer_edit` or `imported_text` origin, update head, commit. No-op edits return the existing revision without writing another one. Model calls never occur inside this transaction.

**Save session:** insert a new session at lock version 1. For an existing session, match its read `lock_version`, update only strategies/progress/status/provenance and increment the version; otherwise return `:stale_session`. Screenplay, base and original request are immutable. Resuming with additional resource allowance appends the explicit allowance to progress/provenance. Never overwrite another worker's saved progress.

**Save candidate:** verify session/base ownership, validate model, insert candidate revision/rows and candidate payload in one transaction. Do not change the accepted head. Saving the same candidate ID/payload is idempotent; different payload with the same ID is an error.

**Accept candidate:** lock screenplay, then candidate decision row; compare head with expected base and candidate base, require structurally valid reviewed result, insert acceptance provenance, set candidate accepted, update head. The resulting revision already exists and is not copied or mutated. Repeating the same acceptance returns the existing acceptance; a different head or changed review payload is a conflict. Semantic concerns can be accepted with an explicit recorded override; structural errors cannot.

**Partial acceptance:** first assemble a new candidate from selected groups and their required dependencies, rerun affected checks and create a fresh review. Accept that result. Never mutate a reviewed candidate or accept only an undocumented subset of its operations.

**Reject:** record rejection; a repeated rejection is idempotent, while an accepted candidate returns `:already_accepted`. Preserve candidate/history for later retrieval. A new editing session can reuse its material. No head change.

**Report save:** validate all source revisions and evidence references; insert report and source links. Optional `source_models: [model]` supplies unsaved experimental revisions from scene lift/ablation. Validate their existing parent chain and screenplay ownership, insert their immutable rows using the same writer in this transaction, then insert the report. They do not become writing candidates or accepted history merely because analysis used them. An existing revision ID must have identical content; conflicting content is rejected. Historical/candidate reports are valid even when the head has moved. No head comparison is needed because source revisions are immutable. Display currentness separately.

**Undo/recovery:** copy selected historical authored content into a new candidate whose parent is the current head. Never move the head backward and erase accepted history. Whole-draft undo uses the same mechanism.

## History and query policy

Accepted history follows parent IDs from the current accepted head, newest first. Candidate history is available by session or explicit inclusion; rejected branches do not appear as accepted drafts. History paging uses a revision cursor, not wall-clock assumptions. SQL queries always include screenplay and revision scope.

Load each revision with a fixed collection of ordered queries; avoid one query per scene or element. Bulk insert full revision rows with `insert_all` within the transaction and deferred cyclic foreign keys. Rebuild indexes, outline and block views once after loading. Store all values needed to reconstruct those views, including dual side, attributes and canonical markup. No current-only projection tables remain.

The app treats revision rows, structural rows, artifacts, reports and candidate payloads as immutable. Updates are only exposed for head pointers, session progress and candidate decisions. Administrative SQL is outside this application contract; no extra trigger framework is required.
