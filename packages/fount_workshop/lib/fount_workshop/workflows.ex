defmodule FountWorkshop.Workflows do
  @moduledoc "Nine writer actions; each creates actual candidate pages unless exploration or diagnosis was explicitly requested."
  for workflow <-
        ~w(develop alternatives propagate sequence character notes pass recover investigate) do
    name = String.to_atom(workflow)

    def unquote(name)(model, request, services, opts \\ []) do
      request = Map.put(request, "workflow", unquote(workflow))
      FountWorkshop.Session.start(model, request, services, opts)
    end
  end
end
