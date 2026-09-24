defmodule Fount.Persistence.Query do
  @moduledoc "Composable Ecto queries over Fount's current screenplay projection."

  import Ecto.Query

  alias Fount.Persistence.Schema

  @doc "Ordered scenes for one screenplay, optionally including omitted scenes."
  def scenes(screenplay_id, opts \\ []) do
    include_omitted? = Keyword.get(opts, :include_omitted, false)

    from(scene in Schema.Scene,
      where: scene.screenplay_id == ^screenplay_id and (^include_omitted? or not scene.omitted),
      order_by: scene.ordinal
    )
  end

  @doc "Cast entries in display-name order."
  def cast(screenplay_id) do
    from(character in Schema.Character,
      where: character.screenplay_id == ^screenplay_id,
      order_by: [character.display_name, character.id]
    )
  end

  @doc "Authored storyline assertions, optionally limited to one named thread."
  def storylines(screenplay_id, thread \\ nil) do
    base =
      from(assertion in Schema.Assertion,
        where:
          assertion.screenplay_id == ^screenplay_id and assertion.namespace == "writer" and
            assertion.kind == "storyline"
      )

    if is_nil(thread),
      do: base,
      else: from(assertion in base, where: assertion.value["data"]["thread"] == ^thread)
  end

  @doc "Visible scenes tagged with one authored storyline, in screenplay order."
  def scenes_for_storyline(screenplay_id, thread) do
    from(scene in Schema.Scene,
      join: assertion in Schema.Assertion,
      on: assertion.target_id == scene.id,
      where:
        scene.screenplay_id == ^screenplay_id and not scene.omitted and
          assertion.screenplay_id == ^screenplay_id and assertion.namespace == "writer" and
          assertion.kind == "storyline" and assertion.value["data"]["thread"] == ^thread,
      distinct: true,
      order_by: scene.ordinal
    )
  end

  @doc "Evidence for one character, with role/status retained for caller interpretation."
  def mentions(screenplay_id, character_id) do
    from(mention in Schema.Mention,
      join: element in Schema.Element,
      on: element.id == mention.element_id,
      where: mention.screenplay_id == ^screenplay_id and mention.character_id == ^character_id,
      order_by: [element.ordinal, mention.byte_start],
      select: %{mention: mention, element: element}
    )
  end

  @doc "Dialogue turns explicitly linked to a character through confirmed cue evidence."
  def dialogue_for(screenplay_id, character_id) do
    from(turn in Schema.DialogueTurn,
      join: cue in Schema.Element,
      on: cue.id == turn.cue_element_id,
      join: mention in Schema.Mention,
      on: mention.element_id == cue.id,
      where:
        turn.screenplay_id == ^screenplay_id and mention.character_id == ^character_id and
          mention.role == "speaker_cue" and mention.status == "confirmed",
      order_by: turn.ordinal,
      select: %{turn: turn, cue: cue}
    )
  end

  @doc "Scenes with a confirmed speaking cue or named action evidence for a character."
  def scenes_with(screenplay_id, character_id, opts \\ []) do
    include_suggestions? = Keyword.get(opts, :include_suggestions, false)
    statuses = if include_suggestions?, do: ["confirmed", "suggested"], else: ["confirmed"]

    from(scene in Schema.Scene,
      join: element in Schema.Element,
      on: element.scene_id == scene.id,
      join: mention in Schema.Mention,
      on: mention.element_id == element.id,
      where:
        scene.screenplay_id == ^screenplay_id and mention.character_id == ^character_id and
          mention.status in ^statuses and mention.role in ["speaker_cue", "action"],
      distinct: true,
      order_by: scene.ordinal
    )
  end
end
