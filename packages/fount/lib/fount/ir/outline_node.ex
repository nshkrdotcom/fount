defmodule Fount.IR.OutlineNode do
  @moduledoc "Writer-facing section hierarchy derived from Fountain sections."

  @enforce_keys [:id, :section_element_id, :level, :title]
  defstruct [:id, :section_element_id, :level, :title, :parent_id, :child_ids, :scene_ids]
  @type t :: %__MODULE__{}
end
