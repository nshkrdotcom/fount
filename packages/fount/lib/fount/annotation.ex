defmodule Fount.Annotation do
  @moduledoc "Derived, source-addressable information that is deliberately not screenplay truth."

  @enforce_keys [:id, :namespace, :kind, :target, :value, :provenance]
  defstruct [:id, :namespace, :kind, :target, :value, :provenance, :confidence, :dependencies]
  @type t :: %__MODULE__{}
end
