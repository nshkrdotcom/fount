defmodule Fount.IR.TitlePage do
  @moduledoc "Structured title-page entries while retaining source spans."

  defmodule Entry do
    @moduledoc false
    @enforce_keys [:id, :key, :values]
    defstruct [:id, :key, :values, :span, :raw]
    @type t :: %__MODULE__{}
  end

  defstruct entries: []
  @type t :: %__MODULE__{entries: [Entry.t()]}
end
