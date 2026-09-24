# Cast and Mentions

Screenplay characters are not mere text strings. In production and story development, character identity, speaking cues, aliases, and mentions in action lines represent fundamentally different kinds of data.

Fount decouples character reality into three distinct relational layers:
1. **Canonical Characters (`Fount.Cast.Character`)** — The authored entity with a durable UUID.
2. **Aliases (`Fount.Cast.Alias`)** — Surface names and variants linked to that character.
3. **Mentions (`Fount.Cast.Mention`)** — Exact byte-anchored occurrences in script elements.

---

## 1. Authored Characters

A canonical character is defined by the writer:

```elixir
alias Fount.Cast.Character

character = %Character{
  id: Fount.Id.v4(),
  screenplay_id: script.id,
  display_name: "Sarah Connor",
  notes: "Protagonist. Hardened resistance fighter.",
  attributes: %{
    "status" => "lead",
    "arc" => "survival to leader"
  }
}
```

Canonical characters are format-independent: they exist whether the script is exported to Fountain, FDX, or stored in PostgreSQL.

---

## 2. Character Aliases

In screenplay text, characters are referred to in varied ways across cues, action, and dialogue. The alias catalog maps those surface representations to canonical IDs:

```elixir
alias Fount.Cast.Alias

aliases = [
  %Alias{
    character_id: character.id,
    alias: "SARAH",
    normalized_alias: "SARAH",
    kind: :cue # Used in dialogue cue headings
  },
  %Alias{
    character_id: character.id,
    alias: "Sarah",
    normalized_alias: "SARAH",
    kind: :name # Formal name in action/description
  },
  %Alias{
    character_id: character.id,
    alias: "Mom",
    normalized_alias: "MOM",
    kind: :address # Spoken addressee in dialogue
  }
]
```

### Alias Kinds
* `:cue` — Standard uppercase character dialogue cues (e.g. `SARAH (O.S.)`).
* `:name` — Third-person name occurrences in scene action lines.
* `:address` — Direct address by other characters in dialogue.
* `:other` — Nicknames, disguised names, or code names.

---

## 3. Byte-Anchored Mentions

Every time a character appears or is referenced in an element, Fount records an occurrence in `Fount.Cast.Mention`:

```elixir
alias Fount.Cast.Mention

mention = %Mention{
  id: Fount.Id.v4(),
  screenplay_id: script.id,
  element_id: element.id,
  character_id: character.id,
  surface: "SARAH",
  byte_start: 0,
  byte_end: 5,
  role: :speaker_cue,
  status: :confirmed,
  producer: "fount.parser",
  confidence: 1.0,
  model_revision_id: script.revision.id
}
```

### Mention Roles
* `:speaker_cue` — The character is speaking this dialogue turn.
* `:action` — The character is explicitly present or described in an action block.
* `:dialogue_reference` — Another character mentions this character in spoken dialogue.
* `:parenthetical` — The character is referenced in actor direction.

### Resolution Statuses
* `:confirmed` — Explicit, verified association (e.g. an unambiguous uppercase cue).
* `:suggested` — Candidate match identified by an analyzer or model.
* `:ambiguous` — Multiple characters share an alias (e.g., two characters named "JOHN"); requires writer confirmation.

---

## 4. Querying Presence vs. Reference

Because mentions record roles and element IDs, relational queries can answer precise dramatic questions:

```elixir
# Who is physically present in Scene 14?
present_characters = Fount.Persistence.Query.characters_in_scene(
  Fount.Repo, 
  screenplay_id, 
  scene_id,
  roles: [:speaker_cue, :action]
)

# Where is Sarah mentioned behind her back?
unseen_mentions = Fount.Persistence.Query.dialogue_mentions_without_presence(
  Fount.Repo,
  screenplay_id,
  character.id
)
```

---

## 5. Renames and Phrasing Ripple Effects

In screenplays, renaming a character is almost never a blind find-and-replace. If `BOB` becomes `ROBERT`, pronouns, tone, formality, and rhyme in surrounding dialogue may need adjustment.

Fount treats renames as a **structured plan**:
1. **Mechanical Updates:** Cue elements linked to the character are updated deterministically.
2. **Reviewable Candidates:** Mentions in action, dialogue, and parentheticals generate reviewable edit proposals.
3. **Agentic Phrasing Pass:** Surrounding dialogue lines are flagged for writer review or passed to an agent to evaluate dialogue rhythm and pronouns.
