# Fount and System One architecture

Source snapshots reviewed on 2026-09-30:

| System | Source commit | Views |
| --- | --- | --- |
| [Fount](FOUNT_ARCHITECTURE.md) | `de5e9549794368bf38ab774bdf304ce4c76c28ca` | Context, package dependencies, analysis, editing/acceptance, runtime, stored data, Core representation |
| [System One SDK](SYSTEM_ONE_SDK_ARCHITECTURE.md) | `155c3309892dfacdebe2a2f1256fa71e03dc545d` | Ecosystem, SDK components, evaluation, batch lifecycle, native runtime |

Read each document from the system view down to the implementation views. These are maps of the checked-in implementation, not feature promises or runtime certification. Arrows have a stated meaning per diagram; a package dependency is not necessarily a network call.

Current import workflow and debugging: [IMPORT_WORKFLOW.md](IMPORT_WORKFLOW.md), including parser audit, exact call records and source self-review.

## Markdown notation

Use fenced `mermaid` blocks, with stable `flowchart`, `sequenceDiagram` and `erDiagram` syntax. Flowcharts with named subgraphs remain suitable for software components and package boundaries. Organize them into context/component levels following the [C4 model](https://c4model.com/diagrams), without requiring Mermaid's experimental C4 renderer.

Mermaid now offers [architecture diagrams](https://mermaid.js.org/syntax/architecture) starting with `architecture-beta` (v11.1+), primarily for cloud/service resources. Its [C4 syntax](https://mermaid.js.org/syntax/c4) is explicitly experimental. Neither offers enough benefit here to require beta syntax or custom icon registration. Sequence and ER diagrams express execution order and stored relationships more directly than a single giant flowchart.

[GitHub renders Mermaid fences in Markdown](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-diagrams). Other Markdown viewers need Mermaid support. The blocks use Mermaid YAML configuration for the built-in neutral theme. These files avoid custom CSS, external icons and renderer-specific layouts; rendering still depends on the viewer's Mermaid version. New syntax is not inherently a better architecture model.

## Scope and validation

The diagrams cover the important modules, boundaries, persistence and execution paths, rather than every function or table. Source links in each document are pinned to the reviewed commit. Optional and unfinished components are labeled explicitly.

All 12 Mermaid blocks were rendered successfully with Mermaid CLI 12.0.0 (Mermaid 12.0.0) using local Chromium before publication. Commit-pinned source paths and local Markdown links were checked. No application source or Phase 08 certification documents were changed.
