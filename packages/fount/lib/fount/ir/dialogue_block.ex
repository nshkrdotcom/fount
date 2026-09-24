defmodule Fount.IR.DialogueBlock do
  @moduledoc "Character cue plus its dialogue/parenthetical elements."

  @enforce_keys [:id, :cue_id, :body_ids]
  defstruct [:id, :cue_id, :body_ids, :source_span, :dual_with, :side]
  @type t :: %__MODULE__{}
end
