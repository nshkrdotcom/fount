defmodule Fount.IR.Scene do
  @moduledoc "Scene view over the canonical flat element stream."

  @enforce_keys [:id, :heading_id, :element_ids]
  defstruct [:id, :heading_id, :element_ids, :source_span, :number, :outline_path, omitted?: false]
  @type t :: %__MODULE__{}
end
