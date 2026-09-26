defmodule FountWorkshop.TestSupport.ScriptedCompletion do
  @moduledoc false
  @behaviour Inference.Adapter
  @impl true
  def provider_kind, do: :model_endpoint
  @impl true
  def complete(client, request) do
    agent = Keyword.fetch!(client.adapter_opts, :script)

    item =
      Agent.get_and_update(agent, fn
        [next | remaining] -> {next, remaining}
        [] -> {:exhausted_script, []}
      end)

    case item do
      :exhausted_script ->
        {:error, Inference.Error.provider_error(:unexpected_extra_completion)}

      {:error, reason} ->
        {:error, Inference.Error.provider_error(reason)}

      f when is_function(f, 1) ->
        value = f.(request)

        {:ok,
         Inference.Response.new(
           text: Jason.encode!(value),
           model: "offline-script",
           finish_reason: :stop
         )}
    end
  end
end
