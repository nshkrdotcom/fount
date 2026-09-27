defmodule Fount.Observe.PhaseSevenLensAssetsTest do
  use ExUnit.Case, async: true

  alias Fount.Observe.{Context, Lens, Registry}

  @lenses ~w(audience.reader_experience sequence.movement dialogue.exchange setup_payoff.motifs)

  test "Phase-7 lenses are installed closed declarative assets" do
    for id <- @lenses do
      assert Registry.lens?(id)
      assert {:ok, asset} = Lens.load(id)
      assert asset["output_contract"] == "observe.answer_set"
      assert asset["context_contract"]["allow_unknown"] == false
      refute Map.has_key?(asset, "module")
      refute Map.has_key?(asset, "function")
    end
  end

  test "dialogue exchange accepts only declared neutral typed context slots" do
    assert {:ok, lens} = Lens.load("dialogue.exchange")

    assert {:ok, context} =
             Context.from_map(
               %{
                 "slots" => %{
                   "speaker_beliefs" => [
                     %{
                       "owner" => "Mara",
                       "proposition" => "Dan knows what D.R. means",
                       "stance" => "believes",
                       "probability" => 0.9
                     }
                   ],
                   "prior_turns" => [
                     %{
                       "speaker" => "Mara",
                       "text" => "You said it was gone.",
                       "channel" => "dialogue"
                     }
                   ]
                 }
               },
               lens["context_contract"]
             )

    assert Enum.sort(Map.keys(context.slots)) == ["prior_turns", "speaker_beliefs"]

    assert {:error, _} =
             Context.from_map(
               %{"slots" => %{"intelligence_state" => %{"future" => true}}},
               lens["context_contract"]
             )
  end
end
