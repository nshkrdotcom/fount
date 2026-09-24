defmodule Fount.Analyzer do
  @moduledoc "Behavior for deterministic or model-backed screenplay analyzers."

  @callback analyze(Fount.Document.t(), keyword()) ::
              {:ok, [Fount.Annotation.t()]} | {:error, term()}
end
