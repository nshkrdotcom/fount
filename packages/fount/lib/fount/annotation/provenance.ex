defmodule Fount.Annotation.Provenance do
  @moduledoc "How and against which source revision an annotation was produced."
  @enforce_keys [:producer]
  defstruct [:producer, :producer_version, :model, :source_revision, :created_at, :metadata]
  @type t :: %__MODULE__{}
end
