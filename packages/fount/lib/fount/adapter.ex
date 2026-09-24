defmodule Fount.Adapter do
  @moduledoc "Shared adapter result types."

  defmodule ImportResult do
    @moduledoc "An imported canonical document with fidelity diagnostics."
    @enforce_keys [:document]
    defstruct [:document, diagnostics: [], losses: [], metadata: %{}]
    @type t :: %__MODULE__{}
  end

  defmodule ExportResult do
    @moduledoc "Exported adapter data with fidelity diagnostics."
    @enforce_keys [:data]
    defstruct [:data, diagnostics: [], losses: [], metadata: %{}]
    @type t :: %__MODULE__{}
  end
end
