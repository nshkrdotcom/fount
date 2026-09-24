# Workshop Architecture

Fount Workshop is the application and orchestration layer built on top of the [Fount](https://hexdocs.pm/fount) screenplay engine. While Fount provides the canonical domain model, AST/CST parsers, and relational persistence, Fount Workshop provides the tools writers and agents need to draft, revise, inspect, and rehearse screenplays.

---

## 1. The Poncho Package Boundary

Fount and Fount Workshop are structured as a poncho repository (two independent Mix packages in the same Git tree):

```text
packages/
├── fount/             # Functional core: IR, CST, Cast, Persistence (Ecto)
└── fount_workshop/    # Workshop shell: AI revision loop, PDF export, Table reads
```

### Why This Separation Matters
* **Zero Bloat in Core:** The core engine (`Fount`) has zero dependencies on LLM clients, Node.js, TTS engines, or external renderers. It compiles quickly and remains purely functional.
* **Separation of Concerns:** `Fount` owns the database schema, Ecto migrations, and screenplay validity rules. `FountWorkshop` is an application that consumes those APIs to run agentic editing and rendering workflows.

---

## 2. The Four-Stage Revision Cycle

All agentic and automated writing workflows in the workshop operate through a strictly bounded four-stage cycle:

```text
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ 1. CONTEXT   │ ──> │ 2. PROPOSE   │ ──> │  3. PREVIEW  │ ──> │  4. ACCEPT   │
│ Read script  │     │ Call model   │     │ Render diffs │     │ Single atomic│
│ at rev R     │     │ return ops   │     │ Side-effect  │     │ transaction  │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
                                                 │
                                                 ▼ (Writer Rejection)
                                          ┌──────────────┐
                                          │ Discarded    │
                                          │ 0 DB changes │
                                          └──────────────┘
```

1. **Context:** Relational queries extract only the relevant scene elements, characters, and surrounding turns at a fixed revision `R`.
2. **Propose:** An LLM or generator proposes bounded, structured operations (e.g. `replace_text`, `set_scene_heading`).
3. **Preview:** Pure transformations generate an in-memory preview showing exact semantic and textual diffs. If the writer rejects it, the preview is dropped with **zero database mutation**.
4. **Accept:** If approved, a single atomic transaction commits the revised model, advances the revision hash, records provenance, and updates relational rows.

---

## 3. Transactional Safety & Optimistic Locking

To prevent race conditions when multiple agents or external editors modify a script, `FountWorkshop.accept/5` checks `expected_revision`:

```elixir
case FountWorkshop.accept(Fount.Repo, "my-script", preview, base_revision_id) do
  :ok ->
    # Successfully committed
    :ok

  {:error, {:conflict, current_revision}} ->
    # The script was modified since the context was extracted.
    # The proposal is safely rejected without corrupting state.
    {:error, :concurrent_edit_detected}
end
```
