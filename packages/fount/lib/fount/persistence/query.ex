defmodule Fount.Persistence.Query do
  @moduledoc "Relational queries always name the screenplay AND immutable revision."
  import Ecto.Query
  alias Fount.Persistence.Schema

  def scenes(screenplay, revision, opts \\ []) do
    omitted = Keyword.get(opts, :include_omitted, false)

    from(s in Schema.Scene,
      where: s.screenplay_id == ^screenplay and s.revision_id == ^revision and (^omitted or not s.omitted),
      order_by: s.ordinal
    )
  end

  def cast(screenplay, revision),
    do:
      from(c in Schema.Character,
        where: c.screenplay_id == ^screenplay and c.revision_id == ^revision,
        order_by: [c.display_name, c.id]
      )

  def storylines(screenplay, revision),
    do:
      from(a in Schema.AuthoredItem,
        where: a.screenplay_id == ^screenplay and a.revision_id == ^revision and a.kind == "storyline"
      )

  def mentions(screenplay, revision, character) do
    from(m in Schema.Mention,
      join: e in Schema.Element,
      on: e.screenplay_id == m.screenplay_id and e.revision_id == m.revision_id and e.id == m.element_id,
      where: m.screenplay_id == ^screenplay and m.revision_id == ^revision and m.character_id == ^character,
      order_by: [e.ordinal, m.byte_start],
      select: %{mention: m, element: e}
    )
  end

  def mention_candidates(screenplay, revision, character) do
    from(m in Schema.Mention,
      join: c in Schema.MentionCandidate,
      on: c.screenplay_id == m.screenplay_id and c.revision_id == m.revision_id and c.mention_id == m.id,
      where: m.screenplay_id == ^screenplay and m.revision_id == ^revision and c.character_id == ^character,
      select: m
    )
  end

  def dialogue_for(screenplay, revision, character) do
    from(b in Schema.DialogueBlock,
      join: m in Schema.Mention,
      on: m.screenplay_id == b.screenplay_id and m.revision_id == b.revision_id and m.element_id == b.cue_element_id,
      where:
        b.screenplay_id == ^screenplay and b.revision_id == ^revision and m.character_id == ^character and
          m.status == "confirmed" and m.role == "speaker_cue",
      order_by: b.ordinal,
      select: b
    )
  end

  def scenes_with(screenplay, revision, character) do
    from(s in Schema.Scene,
      join: e in Schema.Element,
      on: e.screenplay_id == s.screenplay_id and e.revision_id == s.revision_id and e.scene_id == s.id,
      join: m in Schema.Mention,
      on: m.screenplay_id == e.screenplay_id and m.revision_id == e.revision_id and m.element_id == e.id,
      where:
        s.screenplay_id == ^screenplay and s.revision_id == ^revision and m.character_id == ^character and
          m.status == "confirmed" and m.role == "speaker_cue",
      distinct: true,
      order_by: s.ordinal
    )
  end

  def search(screenplay, revision, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(e in Schema.Element,
      where:
        e.screenplay_id == ^screenplay and e.revision_id == ^revision and
          fragment("to_tsvector('simple', ?) @@ websearch_to_tsquery('simple', ?)", e.text, ^query),
      order_by: e.ordinal,
      limit: ^limit
    )
  end
end
