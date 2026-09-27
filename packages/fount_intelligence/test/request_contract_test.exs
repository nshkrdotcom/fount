defmodule Fount.Intelligence.RequestContractTest do
  use ExUnit.Case, async: true
  alias Fount.Intelligence.Playbooks.{Registry, Request}

  test "closed playbooks reject executable names, unknown keys and duplicate request IDs" do
    model = Fount.Screenplay.new()
    params = %{"selection" => %{"whole_screenplay" => true}, "include_summaries" => false}
    request = %{"id" => "inspect", "playbook" => "inventory", "params" => params}
    assert {:ok, parsed} = Request.parse(model, request)
    assert Request.to_map(parsed) == request
    assert {:error, :duplicate_playbook_request_id} = Request.parse_many(model, [request, request])
    assert {:error, _} = Request.parse(model, Map.put(request, "module", "System"))
    assert {:error, :unknown_playbook} = Registry.validate(model, "System.cmd", %{})
    assert {:error, _} = Registry.validate(model, "inventory", Map.put(params, "save_to", "/private"))
    assert length(Registry.names()) == 16
  end

  test "provider-free inspection leaves source and revision untouched" do
    model = Fount.Screenplay.new(scenes: [%{heading: "INT. ROOM - DAY", elements: [%{type: :action, text: "A locked door."}]}])
    original = Fount.Screenplay.to_fountain(model)
    request = %{"id" => "read", "playbook" => "inventory", "params" => %{"selection" => %{"whole_screenplay" => true}, "include_summaries" => false}}
    assert {:ok, [_result]} = Fount.Intelligence.execute(model, [request], %{})
    assert Fount.Screenplay.to_fountain(model) == original
  end
end
