defmodule Fount.Intelligence.ContextBuilderTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.Acquisition.ContextBuilder
  alias Fount.Intelligence.Diagnosis.Concern
  alias Fount.Observe.Context

  test "rich state becomes Observe primitives under the installed closed context contract" do
    {:ok, concern} = Concern.new("The exchange loses pressure.")

    state = %{
      "known_facts" => [
        %{
          "subject" => "Mara",
          "predicate" => "knows",
          "object" => "the door is locked",
          "stance" => "asserted",
          "evidence_ids" => []
        }
      ],
      "speaker_beliefs" => [
        %{
          "owner" => "Mara",
          "proposition" => "Dan is bluffing",
          "stance" => "uncertain",
          "probability" => 0.6
        }
      ]
    }

    assert {:ok, %Context{} = context} =
             ContextBuilder.build("diagnosis.evidence_support", concern, state, [])

    assert Context.semantic_map(context)["slots"]["known_facts"] == [
             %{
               "subject" => "Mara",
               "predicate" => "knows",
               "object" => "the door is locked",
               "stance" => "asserted"
             }
           ]
  end

  test "unknown context slots fail before acquisition" do
    {:ok, concern} = Concern.new("The exchange loses pressure.")

    assert {:error, error} =
             ContextBuilder.build(
               "diagnosis.evidence_support",
               concern,
               %{"arbitrary_attributes" => %{"anything" => true}},
               []
             )

    assert inspect(error) =~ "invalid_context"
  end

  test "Intelligence structs never cross the Observe context boundary" do
    {:ok, concern} = Concern.new("The exchange loses pressure.")

    assert {:error, _} =
             ContextBuilder.build(
               "diagnosis.evidence_support",
               concern,
               %{"known_facts" => [concern]},
               []
             )
  end
end
