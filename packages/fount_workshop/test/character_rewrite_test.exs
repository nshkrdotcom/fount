defmodule FountWorkshop.CharacterRewriteTest do
  use ExUnit.Case, async: true

  alias Fount.{Query, Screenplay}
  alias FountWorkshop.CharacterRewrite

  test "a three-scene character pass rewrites his dialogue and partner replies" do
    raw = """
    INT. OFFICE - DAY

    DAN
    I can explain the ledger.

    MARA
    Then explain it.

    EXT. SHED - DUSK

    DAN
    Take the key.

    MARA
    Why now?

    INT. GATEHOUSE - NIGHT

    DAN
    I will come with you.

    MARA
    Keep up.
    """

    base = raw |> Fount.parse!() |> Screenplay.from_document(cast_resolution: :literal_cues)
    dan = Enum.find(Query.characters(base), &(&1.display_name == "DAN"))
    scene_ids = Enum.map(base.ir.scenes, & &1.id)
    assert {:ok, ids} = CharacterRewrite.targets(base, dan.id, scene_ids)
    assert length(ids) == 6

    replacements =
      ids
      |> Enum.with_index()
      |> Enum.map(fn {id, index} ->
        %{"element_id" => id, "text" => "Revised response #{index + 1}."}
      end)

    client =
      Inference.Client.new!(
        adapter: Inference.Adapters.Mock,
        provider: :mock,
        adapter_opts: [response_text: Jason.encode!(%{"changes" => replacements})]
      )

    assert {:ok, proposal} =
             CharacterRewrite.propose(
               base,
               dan.id,
               scene_ids,
               "Dan moves from evasion to taking responsibility; Mara pushes back.",
               client
             )

    assert Enum.map(proposal.screenplay.ir.scenes, & &1.id) == scene_ids

    assert Enum.all?(
             ids,
             &String.starts_with?(
               Query.node(proposal.screenplay, &1).text,
               "Revised response"
             )
           )

    assert Query.node(base, hd(ids)).text == "I can explain the ledger."
  end
end
