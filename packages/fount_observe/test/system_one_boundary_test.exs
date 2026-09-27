defmodule Fount.Observe.SystemOneBoundaryTest do
  use ExUnit.Case, async: true
  alias Fount.Observe.{Provider, Question, Request}
  alias SystemOneSDK.Test, as: SDKTest

  defp body do
    %{"model" => "fixture", "usage" => %{"input_tokens" => 3, "output_tokens" => 2},
      "answers" => %{
        "visible" => %{"type" => "noul", "noul" => 0.9},
        "tactic" => %{"type" => "choice", "choice" => "evade", "confidence" => 0.4,
          "probabilities" => %{"evade" => 0.8, "answer" => 0.2}},
        "pressure" => %{"type" => "score", "score" => 0.3, "confidence" => 0.6,
          "legend" => %{"0" => "low", "1" => "high"},
          "probabilities" => %{"0" => 0.7, "1" => 0.3}}
      }}
  end

  defp handle(client), do: %Provider{sensor_id: "system_one", state: %{client: client},
    fingerprint: %{"provider" => "fixture-transport", "model" => "fixture", "stability" => "immutable_exact"}}
  defp requests do
    model = Fount.Screenplay.new()
    for id <- ["a", "b"] do
      {:ok, request} = Request.new(model, id, %{"passage" => "Mara looks away."})
      request
    end
  end
  defp questions do
    [visible: Question.noul("Can this action be filmed?"),
      tactic: Question.choice("Which tactic?", evade: "Evade", answer: "Answer"),
      pressure: Question.score("Pressure?", ["low", "high"])]
  end

  test "real SDK serialization, enrichment and batch identity terminate at the adapter" do
    client = SDKTest.client() |> SDKTest.stub_response(body())
    on_exit(fn -> SDKTest.close(client) end)
    assert {:ok, batch} = Fount.Observe.evaluate(handle(client), requests(), questions(), max_concurrency: 2)
    assert batch.status == :complete
    assert Enum.map(batch.entries, & &1.request_id) == ["a", "b"]
    for entry <- batch.entries do
      values = Map.new(entry.observations, &{&1.kind, &1.result.distribution})
      assert values["visible"].confidence == nil
      assert values["tactic"].values == [{"evade", 0.8}, {"answer", 0.2}]
      assert values["pressure"].scalar == 0.3
      assert values["pressure"].confidence == 0.6
    end
    refute inspect(batch) =~ "SystemOneSDK."
    assert :ok = SDKTest.verify!(client)
    assert length(SDKTest.requests(client)) == 2
  end

  test "an invalid native answer remains an error, not unsupported screenplay evidence" do
    client = SDKTest.client() |> SDKTest.stub_response(put_in(body(), ["answers", "visible", "noul"], 3))
    on_exit(fn -> SDKTest.close(client) end)
    assert {:ok, batch} = Fount.Observe.evaluate(handle(client), requests(), questions())
    assert batch.status == :partial
    assert Enum.all?(batch.entries, &(&1.observations == [] and &1.status == :error))
    assert :ok = SDKTest.verify!(client)
  end

  test "provider errors discard bodies and credentials" do
    client = SDKTest.client() |> SDKTest.stub_http_error(401, body: %{"secret" => "never-record-this"})
    on_exit(fn -> SDKTest.close(client) end)
    assert {:ok, batch} = Fount.Observe.evaluate(handle(client), requests(), questions())
    assert batch.status == :partial
    refute inspect(batch) =~ "never-record-this"
    refute inspect(handle(client)) =~ "typesafe-test-key"
  end

  test "a whole-call timeout returns promptly and does not manufacture observations" do
    parent = self()
    client = SDKTest.client() |> SDKTest.stub_callback(fn _request ->
      send(parent, {:started, self()})
      receive do
        :release -> {:response, body()}
      after
        5_000 -> {:response, body()}
      end
    end)
    on_exit(fn -> SDKTest.close(client) end)
    task = Task.async(fn -> Fount.Observe.evaluate(handle(client), Enum.take(requests(), 1), questions(), total_timeout_ms: 100) end)
    assert_receive {:started, worker}, 2_000
    assert {:ok, batch} = Task.await(task, 2_000)
    assert hd(batch.entries).error.class == :provider_timeout
    assert hd(batch.entries).observations == []
    # Release a provider that may outlive its caller; cancellation cleanup is
    # also checked by the SDK's lifecycle suite in runtime QC.
    send(worker, :release)
  end
end
