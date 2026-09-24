defmodule FountWorkshop.SequenceRebuildDatabaseIntegrationTest do
  use ExUnit.Case, async: false

  alias Fount.{ID, Persistence, Repo, Screenplay}
  alias FountWorkshop.SequenceRebuild

  setup_all do
    start_supervised!({Repo, url: System.fetch_env!("FOUNT_DATABASE_URL"), pool_size: 2})
    :ok
  end

  test "sequence replacement reopens with retained IDs and unchanged accepted head" do
    key = "sequence-#{ID.v4()}"

    root =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. OFFICE - DAY",
            elements: [%{type: :action, text: "Mara reads the ledger."}]
          },
          %{
            heading: "EXT. SHED - DAY",
            elements: [%{type: :action, text: "Dan takes the brass key."}]
          },
          %{heading: "INT. HALL - DAY", elements: [%{type: :action, text: "The alarm sounds."}]},
          %{heading: "EXT. FERRY - NIGHT", elements: [%{type: :action, text: "The ferry waits."}]}
        ]
      )

    {:ok, _} = Persistence.create(Repo, key, root)
    [office, shed, hall, ferry] = root.ir.scenes

    output = %{
      "approach" => "Collapse the chase",
      "scenes" => [
        %{
          "heading" => "INT. OFFICE - DAY",
          "elements" => [
            %{"type" => "action", "text" => "Mara reads the ledger."},
            %{"type" => "action", "text" => "The alarm sounds behind her."}
          ]
        },
        %{
          "heading" => "EXT. SHED - DAY",
          "elements" => [
            %{"type" => "action", "text" => "Dan takes the brass key."}
          ]
        }
      ]
    }

    client =
      Inference.Client.new!(
        adapter: Inference.Adapters.Mock,
        provider: :mock,
        adapter_opts: [response_text: Jason.encode!(output)]
      )

    assert {:ok, result} =
             SequenceRebuild.run(
               Repo,
               key,
               [office.id, shed.id, hall.id],
               "Make two scenes.",
               client,
               target_scene_count: 2,
               required_texts: ["Dan takes the brass key."]
             )

    assert {:ok, saved} = Persistence.candidate(Repo, result.candidate.id)
    assert Enum.map(saved["screenplay"].ir.scenes, & &1.id) == [office.id, shed.id, ferry.id]
    assert {:ok, head} = Persistence.load(Repo, key)
    assert head.revision.id == root.revision.id
    assert length(head.ir.scenes) == 4
  end
end
