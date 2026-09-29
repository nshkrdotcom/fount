# Phase 06 build and release inventory

Current topology: five independently buildable Phoenix-free libraries plus one non-Hex application host.

| Project | Build/release role |
| --- | --- |
| `packages/fount` | Hex library; canonical screenplay truth and acceptance |
| `packages/fount_observe` | Hex library; neutral measurements/System One boundary |
| `packages/fount_intelligence` | Hex library; evidence-grounded interpretation |
| `packages/fount_workshop` | Hex library; generation/revision, PDF/table-read, Inference/ASM boundary |
| `packages/fount_run` | Hex library; durable orchestration, decisions, approval, delivery |
| `apps/fount_web` | Phoenix application host; not a Hex library and not part of the five-library count |

Root `mix setup` and `mix ci` operate all six workspace projects. Library release hygiene remains `FOUNT_PACKAGE_BUILD=1 mix hex.build` for each of the five libraries. The host is validated by its tests, migration task, asset build, server startup and Playwright acceptance; it is not published as a library package.

The source-writing environment did not resolve the new host Mix lock or Playwright npm lock because no Elixir toolchain/network-resolved package installation was available. Runtime QC must resolve and commit legitimate lockfiles, then rerun the full ladder. Never fabricate dependency checksums.
