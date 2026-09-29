defmodule FountRun.StageHandler do
  @moduledoc "Execution boundary for one durable Run step."

  @callback execute(map(), keyword()) ::
              {:ok, map()} | {:error, term()} | {:partial, term(), map()}
end
