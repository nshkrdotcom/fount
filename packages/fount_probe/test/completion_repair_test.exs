defmodule FountProbe.CompletionRepairTest do
  alias Fount.Writing.Schema
  use ExUnit.Case, async: true

  defmodule ScriptedAdapter do
    @behaviour Inference.Adapter
    @impl true
    def provider_kind, do: :model_endpoint

    @impl true
    def complete(client, request) do
      script = Keyword.fetch!(client.adapter_opts, :script)
      prompt = Inference.Request.user_prompt(request)

      reply =
        Agent.get_and_update(script, fn {[next | rest], prompts} ->
          {next, {rest, [prompt | prompts]}}
        end)

      {:ok, Inference.Response.new(text: reply, model: "script", finish_reason: :stop)}
    end
  end

  test "JSON syntax repair uses the malformed response and still applies the local validator" do
    {:ok, script} = Agent.start_link(fn -> {["{\"value\":", "{\"value\":42}"], []} end)
    client = Inference.Client.new!(adapter: ScriptedAdapter, adapter_opts: [script: script])

    schema = %{
      "type" => "object",
      "properties" => %{"value" => %{"type" => "integer"}},
      "required" => ["value"],
      "additionalProperties" => false
    }

    assert {:ok, %{"value" => 42}, traces} =
             FountProbe.Completion.complete(
               client,
               "ORIGINAL_MARKER: produce a value",
               schema,
               &Schema.validate(schema, &1),
               force_json_text: true,
               decode_repairs: 1
             )

    assert length(traces) == 2
    {[], [repair, original]} = Agent.get(script, & &1)
    assert original =~ "ORIGINAL_MARKER"
    assert repair =~ "{\"value\":"
    refute repair =~ "ORIGINAL_MARKER"
  end
end
