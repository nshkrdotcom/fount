Code.require_file("../support/continuation_store.ex", __DIR__)

defmodule FountWorkshop.AuditionContinuationTest do
  use ExUnit.Case, async: true

  alias FountWorkshop.{Audition, Store}
  alias FountWorkshop.TestSupport.ContinuationStore

  test "whole-screenplay audition exports actual files when no scenes are removed" do
    model =
      Fount.Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :character, text: "MARA"},
              %{type: :dialogue, text: "I have the key."}
            ]
          }
        ]
      )

    {:ok, agent} = ContinuationStore.start_link(model)
    id = Fount.ID.v4()

    {:ok, _} =
      ContinuationStore.save_candidate(agent, "session-1", %{"id" => id, "screenplay" => model})

    services = %{store: %Store{repo: agent, module: ContinuationStore}}
    output = Path.join(System.tmp_dir!(), "fount-audition-#{id}")
    on_exit(fn -> File.rm_rf(output) end)

    assert {:ok, result} =
             Audition.build(id, %{"whole_screenplay" => true}, services, output_dir: output)

    assert result["candidate_id"] == id
    assert File.read!(result["fountain"]) =~ "I have the key."
    assert File.exists?(result["json"].path)
    assert File.exists?(result["html"].path)
  end
end
