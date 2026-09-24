# Scene Revision Loop

The core writing workflow in Fount Workshop is an agent-assisted, writer-reviewed loop. It allows an AI model to draft or refine screenplay scenes while ensuring that the writer maintains complete editorial authority.

The loop consists of four explicit phases: `context → propose → preview → accept`.

---

## 1. Extracting Scene Context

Before calling a model, `FountWorkshop.context/3` extracts the target scene, its ordered elements, and stable element IDs:

```elixir
alias FountWorkshop, as: Workshop

# 1. Load the canonical screenplay from PostgreSQL
{:ok, script} = Fount.Persistence.load(Fount.Repo, "feature-draft")

# 2. Select a scene
scene = hd(script.ir.scenes)

# 3. Extract the bounded context
{:ok, context} = Workshop.context(script, scene.id)
```

The resulting `context` map includes:
* `scene_id` — Stable UUID of the scene being revised.
* `revision` — The screenplay's current model revision hash.
* `elements` — List of element IDs, types, and raw text.
* `characters` — The authored cast catalog for the script.

---

## 2. Generating Proposals via Inference

Proposals are generated using the `Inference` client library. In test or development environments, you can use deterministic mock adapters; in production, you can point to Anthropic, OpenAI, or local models:

```elixir
# Configure the client
client = Inference.client!(
  adapter: Inference.Adapters.OpenAI,
  api_key: System.fetch_env!("OPENAI_API_KEY"),
  model: "gpt-4o"
)

# Request a targeted scene revision
instruction = "Make the dialogue snappier and intensify Sarah's urgency."
{:ok, proposal} = Workshop.propose(context, instruction, client)
```

### Deterministic Testing with Mock Adapters
For unit tests or offline CI, use `Inference.Adapters.Mock`:

```elixir
client = Inference.client!(
  adapter: Inference.Adapters.Mock,
  stub: fn _request ->
    {:ok, %Inference.Response{
      id: "mock_resp_1",
      provider: :mock,
      model: "mock-model",
      text: Jason.encode!(%{
        operations: [
          %{"kind" => "replace_text", "target" => element_id, "value" => "Run."}
        ]
      })
    }}
  end
)
```

---

## 3. Previewing the Diffs

Before any change touches the database, `Workshop.preview/2` applies the proposed operations in memory and computes side-by-side diffs:

```elixir
{:ok, preview} = Workshop.preview(script, proposal)

# Inspect the Myers text diff (additions and deletions)
preview.source_diff

# Inspect structural changes (modified element types, added beats)
preview.semantic_diff

# Review model provenance
preview.inference # => %{provider: :openai, model: "gpt-4o", response_id: "..."}
```

### Writer Rejection
If the proposal is unsatisfactory, the writer simply does nothing or discards the preview. Because previews are pure in-memory values:
* **Zero database rows are written.**
* **The screenplay's revision remains unchanged.**

---

## 4. Atomic Acceptance

If the writer accepts the proposed changes, `Workshop.accept/5` commits the new revision into PostgreSQL:

```elixir
:ok = Workshop.accept(
  Fount.Repo, 
  "feature-draft", 
  preview, 
  script.revision.id
)
```

### Concurrency Protection
If an external writer modified the script while the model was generating, `accept/5` catches the mismatch and returns `{:error, {:stale_revision, actual_id}}`, ensuring no edits are overwritten blindly.
