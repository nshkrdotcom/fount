defmodule FountWorkshop.Writing.Completion do
  @moduledoc "Application completions use the shared Inference boundary and local validators."
  defdelegate complete(client, prompt, schema, validator, opts \\ []), to: FountProbe.Completion
  defdelegate decode(text), to: FountProbe.Completion
end
