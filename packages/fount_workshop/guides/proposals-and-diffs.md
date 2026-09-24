# Proposals and Diffs

Fount Workshop enforces strict boundary control over AI-generated content. Rather than allowing an LLM to dump raw screenplay text back into the system, the model must return structured, targeted edit operations against existing element UUIDs.

---

## 1. Proposal Schema & JSON Schema Enforcement

When calling capable inference models, `FountWorkshop.Proposal.response_format/0` provides a strict JSON Schema:

```json
{
  "type": "object",
  "properties": {
    "operations": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "kind": {"type": "string"},
          "target": {"type": "string"},
          "value": {"type": "string"}
        },
        "required": ["kind", "target", "value"]
      }
    }
  },
  "required": ["operations"]
}
```

This guarantees that models emit parseable operations without hallucinating unexpected keys or formatting marks.

---

## 2. Supported Edit Operations

Proposals decode into `Fount.Edit.Op` structs:

| Operation Kind | Target | Value | Purpose |
| :--- | :--- | :--- | :--- |
| `:replace_text` | Element UUID | String | Replaces dialogue, action, or parenthetical text. |
| `:set_scene_heading` | Scene UUID | String | Updates the scene heading and location/time attributes. |
| `:omit_scene` | Scene UUID | Boolean | Reversibly toggles scene inclusion (`omitted: true/false`). |

### Bounded Target Validation
When `Proposal.decode/2` parses the model payload:
1. Every target ID must exist within the extracted scene context.
2. The model cannot mutate elements outside the requested scene.
3. If an unrecognized ID or invalid operation kind is encountered, decoding fails immediately with a descriptive error.

---

## 3. Side-Effect-Free Previews (`FountWorkshop.Preview`)

When a proposal passes validation, `FountWorkshop.preview/2` constructs an in-memory preview:

```elixir
%FountWorkshop.Preview{
  document: #Fount.Screenplay<...>,
  base_revision: "rev_3a1b...",
  source_diff: [eq: "INT. KITCHEN - NIGHT\n\nSARAH\n", del: "Don't.", ins: "Wait."],
  semantic_diff: %{
    changed_elements: ["el_9921"],
    added_scenes: [],
    omitted_scenes: []
  },
  diagnostics: [],
  inference: %{
    provider: :anthropic,
    model: "claude-3-5-sonnet",
    response_id: "msg_01..."
  }
}
```

### Visualizing Diffs
* **Source Diff (`preview.source_diff`):** Uses Myers diff algorithm to show exact character additions and deletions for text comparison.
* **Semantic Diff (`preview.semantic_diff`):** Highlights affected element UUIDs and structural changes, allowing the UI or CLI to display high-level change cards.

---

## 4. Rejection and Provenance

If the proposal is rejected, no action is required—the preview is discarded by the garbage collector. 

If accepted, the `preview.inference` metadata (model name, provider, response ID) is permanently linked to the resulting revision in the PostgreSQL `acceptances` table, maintaining an auditable chain of custody.
