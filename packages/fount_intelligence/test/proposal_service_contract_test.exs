defmodule Fount.Intelligence.ProposalServiceContractTest do
  use ExUnit.Case, async: true
  alias Fount.Intelligence.Acquisition.Proposals

  test "native host errors and arbitrary trace fields do not escape the proposal boundary" do
    service = fn _, _, _, _ ->
      {:error, %URI{userinfo: "never-record-this"}, [%{"private" => "never-record-this"}]}
    end
    assert {:error, :proposal_service_failed, [%{}]} =
      Proposals.complete(service, "Synthetic input", %{"type" => "object"}, fn _ -> :ok end)
  end

  test "successful proposals are validated locally and traces use neutral JSON fields" do
    service = fn _, _, _, _ ->
      {:ok, %{"summary" => "A door closes."}, [%{"mode" => "json_text", "usage" => %{input_tokens: 4}, "client" => %URI{userinfo: "secret"}}]}
    end
    schema = %{"type" => "object", "required" => ["summary"], "properties" => %{"summary" => %{"type" => "string"}}, "additionalProperties" => false}
    assert {:ok, %{"summary" => "A door closes."}, [trace]} = Proposals.complete(service, "Synthetic input", schema, fn _ -> :ok end)
    assert trace["usage"] == %{"input_tokens" => 4}
    refute Map.has_key?(trace, "client")
  end
end
