# Persistence

Persistence is a boundary, not part of the screenplay model.

## What must be persisted

The Fountain source can reconstruct CST, semantic IR, indexes, scenes, and dialogue blocks. Fount therefore persists only information that cannot safely be regenerated:

- document identity
- semantic identity anchors
- annotations/provenance
- revision metadata

On load, source is parsed again and identities are restored. There is no stale serialized IR competing with Fountain as a second source of truth.

## Filesystem store: default

`Fount.Store.Filesystem` is the recommended default. It stores:

```text
name.fountain
name.fount.json
```

The first file remains ordinary portable Fountain and is friendly to Git and external editors. The sidecar contains Fount-specific identity/analysis metadata. Writes use temporary files plus rename to avoid exposing partially-written individual files.

This is the right default for writers, repositories, CLIs, and local tools.

## SQLite store: application persistence

`Fount.Store.SQLite` is available when the optional `exqlite` dependency is present. It stores the current source/snapshot plus append-only revision records, enables WAL mode, and wraps saves in transactions.

SQLite is appropriate for desktop/server applications that manage many documents or want local revision history without running a database service. Fount talks to Exqlite directly; Ecto is deliberately not part of the core dependency graph.

## Why PostgreSQL is not in the initial package

PostgreSQL solves a different deployment problem: multi-user server persistence, remote concurrency, operational backups, and large shared datasets. Pulling it into a headless screenplay library would impose configuration and server assumptions on every consumer.

A future `packages/...` package can implement the same `Fount.Store` behavior for PostgreSQL without changing the document or edit model. The poncho workspace layout reserves that option.
