defmodule FountWorkshop.NoteResponseTest do
  use ExUnit.Case, async: true

  alias Fount.{Query, Screenplay}
  alias FountWorkshop.NoteResponse

  test "one note yields a targeted edit and only that note is removed in the candidate" do
    raw =
      "INT. OFFICE - NIGHT\n\nMARA\nYou betrayed me.\n\n[[Make the accusation less direct.]]\n\n[[Keep the key visible.]]\n"

    base = raw |> Fount.parse!() |> Screenplay.from_document(cast_resolution: :literal_cues)
    line = Enum.find(base.ir.elements, &(&1.text == "You betrayed me."))
    [note, other] = Enum.filter(base.ir.elements, &(&1.type == :note))

    response = %{
      "changes" => [%{"element_id" => line.id, "text" => "You still have the spare key."}]
    }

    client =
      Inference.Client.new!(
        adapter: Inference.Adapters.Mock,
        provider: :mock,
        adapter_opts: [response_text: Jason.encode!(response)]
      )

    assert {:ok, proposal} = NoteResponse.propose(base, note.id, [line.id], client)
    assert Query.node(proposal.screenplay, line.id).text == "You still have the spare key."
    assert Query.node(proposal.screenplay, note.id) == nil
    assert Query.node(proposal.screenplay, other.id)
    assert Query.node(base, note.id)
    assert Query.node(base, line.id).text == "You betrayed me."
  end
end
