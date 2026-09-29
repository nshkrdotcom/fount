defmodule FountWeb.DemoAdapterTest do
  use ExUnit.Case, async: true

  test "demo adapter is explicit deterministic local endpoint with no credential material" do
    assert FountWeb.DemoAdapter.provider_kind() == :local_model_endpoint
    assert FountWeb.DemoAdapter.credential_mode() == :explicit
    assert FountWeb.DemoAdapter.capabilities(nil) == []

    client = Inference.Client.new!(adapter: FountWeb.DemoAdapter)
    request = Inference.Request.from_prompt!("Investigate this writer's specific creative question")
    assert {:ok, response} = FountWeb.DemoAdapter.complete(client, request)
    assert response.metadata["deterministic"] == true
    assert response.cost == nil
    assert Jason.decode!(response.text)["requests"] != []
  end

  test "fixture contains three scenes, dialogue, and protected train material" do
    raw = FountWeb.Journeys.fixture_fountain()
    {:ok, doc} = Fount.parse(raw)
    root = Fount.Screenplay.from_document(doc, cast_resolution: :literal_cues)
    assert length(root.ir.scenes) >= 3
    assert Enum.any?(root.ir.elements, &(&1.type == :dialogue))
    assert Enum.any?(root.ir.elements, &(String.contains?(&1.text, "departure board")))
  end
end
