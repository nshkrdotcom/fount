# Design Research

Fount's architecture was designed after reviewing mature screenplay editors, modern interchange proposals, screenplay NLP projects, and current Elixir libraries. The implementation is original; these projects were mined for durable design lessons rather than copied as architectures.

## Screenplay systems reviewed

### Beat

Beat demonstrates the value of continuous Fountain parsing, source ranges, persistent line UUIDs, revision ranges, notes, story beats, outline structures, and lookup by identity. Fount generalizes those ideas into a UI-independent source/CST/IR/edit architecture rather than adopting Beat's editor-oriented line model.

- https://github.com/lmparppei/Beat

### Story Architect / STARC

Its mature domain model and reporting code demonstrate what downstream screenplay infrastructure wants: characters, locations, scene beats, timing, page eighths, breakdown resources, scene/cast/dialogue/location reports, and structure/activity projections. Fount treats these as derived projections rather than fields that all belong in canonical screenplay nodes.

- https://starc.app/

### ScreenJSON

ScreenJSON strongly validates typed screenplay elements, stable UUID references, separation of layout from content, and optional derived analysis. Fount keeps those concepts but deliberately does not make a JSON schema the core runtime model.

- https://screenjson.com/
- https://github.com/screenjson/screenjson-schema

### ScreenPy

ScreenPy demonstrates structured shot/scene headings, source positions, nested master/sub-shot concepts, and action/event extraction. Fount adopts the separation between literal text and useful parsed structure while keeping heuristic semantics outside screenplay truth.

- https://github.com/drwiner/ScreenPy

### BookNLP

BookNLP is not a screenplay parser, but its treatment of long-document entities, character-name clustering, coreference, speaker attribution, events, and source offsets is a useful model for an annotation layer with source-grounded provenance.

- https://github.com/booknlp/booknlp

### Open FDX Toolkit and STORYLINER screenplay-parser

These reinforce that FDX/Fountain preprocessing is an adapter concern for downstream AI/preproduction systems. They also provide useful inventories of FDX constructs and practical conversion edge cases.

- https://github.com/sfingali/open-fdx-toolkit
- https://github.com/mcqx4/screenplay-parser

## Fountain

The Fountain 1.1 specification informed parser behavior for title pages, action, scene headings, character/dialogue rules, dual dialogue, sections/synopses, notes, boneyards, page breaks, and emphasis.

- https://fountain.io/syntax/

The parser is custom rather than built around NimbleParsec because exact line/trivia preservation and neighbor-sensitive classification are the primary requirements. This is a design choice, not a claim that parser combinators are unsuitable for all Fountain-related subgrammars.

## Elixir dependencies

The initial package intentionally keeps the dependency surface small:

- `jason` — JSON sidecars/projections
- `saxy` — streaming-oriented XML foundation used by the FDX adapter
- PostgreSQL through Ecto SQL and Postgrex is the application store.
- `stream_data` — property testing for lossless source invariants
- `ex_doc` — development documentation

The pure transformation functions require no running database. Fount also ships an Ecto/PostgreSQL persistence boundary for accepted canonical revisions; web, NLP, and parser-generator frameworks are not required.
