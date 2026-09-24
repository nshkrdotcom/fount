defmodule Fount.IR.Element do
  @moduledoc "A typed canonical screenplay element."

  @enforce_keys [:id, :type, :text]
  defstruct [
    :id,
    :type,
    :text,
    :raw_text,
    :source_span,
    :content_span,
    :inline,
    :attrs,
    :origin
  ]

  @type type ::
          :scene_heading
          | :action
          | :character
          | :dialogue
          | :parenthetical
          | :transition
          | :centered
          | :lyric
          | :section
          | :synopsis
          | :page_break
          | :note
          | :boneyard
          | :blank
          | :unknown

  @type t :: %__MODULE__{
          id: String.t(),
          type: type(),
          text: binary(),
          raw_text: binary() | nil,
          source_span: Fount.Source.Span.t() | nil,
          content_span: Fount.Source.Span.t() | nil,
          inline: list() | nil,
          attrs: map() | nil,
          origin: atom() | nil
        }
end
