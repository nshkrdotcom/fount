defmodule FountWorkshop.CompletionPrivacyTest do
  use ExUnit.Case, async: true
  alias FountWorkshop.Writing.Completion

  test "native provider secrets never enter the completion error contract" do
    error =
      Inference.Error.new(:missing_credentials, :auth, "secret-in-message", %{
        header: "secret-in-header"
      })

    client = Inference.Client.new!(adapter: Inference.Adapters.Mock, adapter_opts: [error: error])

    assert {:error, {:completion_provider_error, :missing_credentials}, []} =
             Completion.complete(client, "Synthetic fixture", %{"type" => "object"}, fn _ ->
               :ok
             end)
  end
end
