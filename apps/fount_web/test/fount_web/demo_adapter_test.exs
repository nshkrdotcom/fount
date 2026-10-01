defmodule FountWeb.DemoAdapterTest do
  use ExUnit.Case, async: true

  test "demo adapter is explicit deterministic local endpoint with no credential material" do
    assert FountWeb.DemoAdapter.provider_kind() == :local_model_endpoint
    assert FountWeb.DemoAdapter.credential_mode() == :explicit
    assert FountWeb.DemoAdapter.capabilities(nil) == []

    client = Inference.Client.new!(adapter: FountWeb.DemoAdapter)

    request =
      Inference.Request.from_prompt!("Investigate this writer's specific creative question")

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
    assert Enum.any?(root.ir.elements, &String.contains?(&1.text, "departure board"))
  end

  test "each deterministic journey passes Workshop preflight" do
    {:ok, doc} = Fount.parse(FountWeb.Journeys.fixture_fountain())
    root = Fount.Screenplay.from_document(doc, cast_resolution: :literal_cues)

    for journey <- FountWeb.Journeys.names() do
      config = FountWeb.Journeys.configuration(root, journey, "test-owner")

      assert {:ok, _} =
               FountWorkshop.Session.preflight(root, config.request, max_repair_rounds: 0)
    end
  end

  test "reveal proposal has a primary change and dependent consequence" do
    client = Inference.Client.new!(adapter: FountWeb.DemoAdapter)
    id = Fount.ID.v4()

    prompt =
      ~s(Write actual complete screenplay pages as canonical typed edits JOURNEY:reveal TARGET_PROTECTED:#{id} AFTER_SCENE:#{id} "base_revision_id":"#{id}" "strategy":{"id":"route-a"})

    request = Inference.Request.from_prompt!(prompt)
    assert {:ok, response} = FountWeb.DemoAdapter.complete(client, request)
    %{"groups" => [primary, dependent]} = Jason.decode!(response.text)
    assert primary["operations"] != []
    assert dependent["depends_on"] == [primary["id"]]
    assert dependent["operations"] != []
  end

  test "repair pass returns one strategy and restores protected material in its proposal" do
    client = Inference.Client.new!(adapter: FountWeb.DemoAdapter)
    id = Fount.ID.v4()
    marker = "JOURNEY:reveal TARGET_PROTECTED:#{id} TARGET_LATE_ACTION:#{id} AFTER_SCENE:#{id}"

    strategy_request =
      Inference.Request.from_prompt!(
        "You are developing choices for a professional spec screenplay. Create exactly 1 genuinely different dramatic approaches"
      )

    assert {:ok, strategy_response} = FountWeb.DemoAdapter.complete(client, strategy_request)
    assert length(Jason.decode!(strategy_response.text)["strategies"]) == 1

    prompt =
      ~s(Write actual complete screenplay pages as canonical typed edits "source_candidate":{"proposal":{"summary":"#{marker}"}} "base_revision_id":"#{id}" "strategy":{"id":"route-a"})

    assert {:ok, response} =
             FountWeb.DemoAdapter.complete(client, Inference.Request.from_prompt!(prompt))

    %{"groups" => [primary, dependent]} = Jason.decode!(response.text)
    assert primary["operations"] |> hd() |> get_in(["target", "id"]) == id
    refute Jason.encode!(primary) =~ "abandons the platform"
    assert dependent["depends_on"] == [primary["id"]]
  end

  test "source alternatives edit only selected unprotected text and remain distinct" do
    id = Fount.ID.v4()
    protected_id = Fount.ID.v4()
    base = Fount.ID.v4()

    context = %{
      "base_revision_id" => base,
      "request" => %{
        "workflow" => "alternatives",
        "options" => %{"protected_text" => [%{"target" => %{"id" => protected_id}}]}
      },
      "selected_pages" => [
        %{
          "type" => "dialogue",
          "target" => %{"kind" => "element", "id" => id},
          "text" => "Try me."
        },
        %{
          "type" => "dialogue",
          "target" => %{"kind" => "element", "id" => protected_id},
          "text" => "Exact surroundings."
        }
      ]
    }

    proposals =
      for strategy <- ["route-a", "route-b"] do
        prompt =
          "Write actual complete screenplay pages as canonical typed edits\n" <>
            Jason.encode!(%{"context" => context, "strategy" => %{"id" => strategy}})

        {:ok, response} =
          FountWeb.DemoAdapter.complete(nil, Inference.Request.from_prompt!(prompt))

        proposal = Jason.decode!(response.text)
        assert proposal["base_revision_id"] == base
        [group] = proposal["groups"]
        [operation] = group["operations"]
        assert operation["target"]["id"] == id
        operation["value"]
      end

    assert length(Enum.uniq(proposals)) == 2
  end
end
