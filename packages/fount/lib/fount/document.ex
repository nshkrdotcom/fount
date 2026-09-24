defmodule Fount.Document do
  @moduledoc "A parsed screenplay with source, CST, semantic IR, annotations, diagnostics, and index."

  @enforce_keys [:id, :revision, :source, :cst, :ir]
  defstruct [:id, :revision, :source, :cst, :ir, :annotations, :diagnostics, :index]

  @type t :: %__MODULE__{
          id: String.t(),
          revision: Fount.Revision.t(),
          source: Fount.Source.t(),
          cst: Fount.Fountain.CST.t(),
          ir: Fount.IR.Script.t(),
          annotations: Fount.Annotations.t(),
          diagnostics: [Fount.Diagnostic.t()],
          index: Fount.Index.t()
        }
end
