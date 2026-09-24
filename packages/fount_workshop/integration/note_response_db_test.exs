defmodule FountWorkshop.NoteResponseDatabaseIntegrationTest do
  use ExUnit.Case, async: false

  alias Fount.{ID, Persistence, Query, Repo, Screenplay}
  alias FountWorkshop.NoteResponse

  setup_all do
    start_supervised!({Repo, url: System.fetch_env!("FOUNT_DATABASE_URL"), pool_size: 2})
    :ok
  end

  test "saved note response removes only its addressed note in the candidate" do
    key = "note-#{ID.v4()}"

    raw =
      "INT. OFFICE - NIGHT\n\nMARA\nYou betrayed me.\n\n[[Make this indirect.]]\n\n[[Keep the key visible.]]\n"

    root = raw |> Fount.parse!() |> Screenplay.from_document(cast_resolution: :literal_cues)
    {:ok, _} = Persistence.create(Repo, key, root)
    line = Enum.find(root.ir.elements, &(&1.text == "You betrayed me."))
    [note, other] = Enum.filter(root.ir.elements, &(&1.type == :note))

    output = %{
      "changes" => [%{"element_id" => line.id, "text" => "You still have the spare key."}]
    }

    client =
      Inference.Client.new!(
        adapter: Inference.Adapters.Mock,
        provider: :mock,
        adapter_opts: [response_text: Jason.encode!(output)]
      )

    assert {:ok, result} = NoteResponse.run(Repo, key, note.id, [line.id], client)
    assert {:ok, saved} = Persistence.candidate(Repo, result.candidate.id)
    assert Query.node(saved["screenplay"], line.id).text == "You still have the spare key."
    assert Query.node(saved["screenplay"], note.id) == nil
    assert Query.node(saved["screenplay"], other.id)
    assert {:ok, head} = Persistence.load(Repo, key)
    assert Query.node(head, note.id)
    assert head.revision.id == root.revision.id
  end
end
