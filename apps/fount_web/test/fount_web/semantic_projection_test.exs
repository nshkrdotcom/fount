defmodule FountWeb.SemanticProjectionTest do
  use ExUnit.Case, async: true

  alias Fount.Screenplay
  alias Fount.Screenplay.Model
  alias Fount.Semantics.SourceInventory
  alias FountWeb.SemanticContext

  test "manual cues are grouped source hypotheses, never one person per speech" do
    source = "INT. ROOM - DAY\n\n" <> String.duplicate("EVAN\nHello.\n\n", 311)
    screenplay = source |> Fount.parse!() |> Screenplay.from_document(cast_resolution: :manual)
    inventory = screenplay |> SourceInventory.build() |> Model.plain()
    rows = source_rows(inventory)
    entities = SemanticContext.project_entities(rows, [])

    assert SemanticContext.character_profiles(entities, screenplay, inventory) == []

    assert [%{display_spelling: "EVAN", cue_count: 311, occurrences: occurrences}] =
             SemanticContext.cue_groups(inventory, rows, %{})

    assert length(occurrences) == 311
    assert Enum.all?(occurrences, &is_binary(&1.handle_id))
    assert Screenplay.to_fountain(screenplay) == source
  end

  test "uppercase printed forms remain source candidates until explicitly disposed" do
    source = "INT. OFFICE - DAY\n\nA form reads:\n\nNETWORK + AUDIO\nACCESS AUTHORIZED.\n"
    screenplay = source |> Fount.parse!() |> Screenplay.from_document(cast_resolution: :manual)
    inventory = screenplay |> SourceInventory.build() |> Model.plain()
    rows = source_rows(inventory)
    entities = SemanticContext.project_entities(rows, [])
    assert SemanticContext.character_profiles(entities, screenplay, inventory) == []

    assert [%{display_spelling: "NETWORK + AUDIO"}] =
             SemanticContext.cue_groups(inventory, rows, %{})

    decision = %{
      "literal_element_id" => hd(inventory["character_cues"])["element_id"],
      "disposition" => "non_character"
    }

    assert SemanticContext.cue_groups(inventory, rows, %{"cue_decisions" => [decision]}) == []
  end

  test "negative cue decisions are not resurrected by partial fallback" do
    literal = %{
      "assessment_origin" => "manual",
      "handle_id" => "cue",
      "payload" => %{"element_id" => "printed"}
    }

    assessment = %{
      "status" => "partial",
      "result" => %{
        "cue_decisions" => [
          %{"literal_element_id" => "printed", "disposition" => "non_character"}
        ]
      }
    }

    assert SemanticContext.include_partial_literals([], [literal], assessment) == []
  end

  test "human-reviewed partitions survive a proposed merge or split as explicit conflicts" do
    reviewed = %{
      "handle_id" => "human",
      "payload" => %{
        "support_set" => [
          ["character", "speaker", 0, 4, "cue-a"],
          ["character", "speaker", 20, 24, "cue-b"]
        ]
      }
    }

    split = %{
      "handle_id" => "split",
      "assessment_origin" => "model",
      "payload" => %{
        "support_set" => [["character", "speaker", 0, 4, "cue-a"]],
        "occurrences" => [%{"literal_element_id" => "cue-a"}]
      }
    }

    unrelated = %{
      "handle_id" => "other",
      "assessment_origin" => "model",
      "payload" => %{"support_set" => [["character", "physical_presence", 40, 44, nil]]}
    }

    assert {[^unrelated], [issue]} =
             FountWeb.SemanticPartitions.reconcile([split, unrelated], [reviewed])

    assert issue["reviewed_handle_ids"] == ["human"]
    assert issue["literal_element_ids"] == ["cue-a"]

    merged =
      put_in(
        split,
        ["payload", "support_set"],
        reviewed["payload"]["support_set"] ++ [["character", "speaker", 60, 64, "cue-c"]]
      )

    assert {[], [_]} = FountWeb.SemanticPartitions.reconcile([merged], [reviewed])
  end

  defp source_rows(inventory) do
    Enum.map(inventory["character_cues"], fn cue ->
      %{
        "handle_id" => cue["element_id"],
        "local_id" => cue["local_id"],
        "kind" => "character",
        "label" => cue["literal"],
        "assessment_origin" => "manual",
        "payload" => cue
      }
    end)
  end
end
