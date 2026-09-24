defmodule Fount.WriterTest do
  use ExUnit.Case, async: true

  alias Fount.Screenplay

  test "table read keeps dialogue, direction and confirmed speaker identity in order" do
    model =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - NIGHT",
            elements: [
              %{type: :character, text: "MARA"},
              %{type: :parenthetical, text: "(quietly)"},
              %{type: :dialogue, text: "Are you ready?"},
              %{type: :character, text: "JOHN"},
              %{type: :dialogue, text: "Yes."}
            ]
          }
        ]
      )

    {model, mara} = Screenplay.add_character(model, "Mara")
    mara_cue = Enum.find(model.ir.elements, &(&1.type == :character and &1.text == "MARA"))
    {:ok, model} = Screenplay.link_cue(model, mara_cue.id, mara.id)
    scene = hd(model.ir.scenes)

    assert {:ok, [first, second]} = Fount.Writer.table_read(model, scene.id)
    assert first.character_id == mara.id
    assert first.cue == "MARA"
    assert first.dialogue == "Are you ready?"
    assert first.parentheticals == ["(quietly)"]
    assert second.character_id == nil
    assert second.cue == "JOHN"
    assert second.dialogue == "Yes."

    {:ok, omitted} = Screenplay.apply(model, Fount.Edit.omit_scene(scene.id))
    assert Fount.Writer.table_read(omitted, scene.id) == {:ok, []}
    assert {:ok, [_, _]} = Fount.Writer.table_read(omitted, scene.id, include_omitted: true)
  end

  test "writer projections group locations and authored storylines without changing source" do
    model =
      Screenplay.new(
        scenes: [
          %{heading: "INT. HOUSE - KITCHEN - DAY", elements: [%{type: :action, text: "Mara waits."}]},
          %{heading: "INT. HOUSE - HALL - NIGHT", elements: [%{type: :action, text: "John enters."}]},
          %{heading: "EXT. ROAD - DAY", elements: [%{type: :action, text: "They run."}]}
        ]
      )

    [first, second, third] = model.ir.scenes

    label = %Fount.Annotation{
      id: Fount.ID.v4(),
      namespace: "writer",
      kind: :storyline,
      target: %Fount.Annotation.Target{node_id: first.id},
      value: %{"thread" => "A", "beat" => "Arrival"},
      provenance: %Fount.Annotation.Provenance{producer: "writer"}
    }

    model = %{model | annotations: %{label.id => label}}

    assert Fount.Writer.location_groups(model) == %{"HOUSE" => [first.id, second.id], "ROAD" => [third.id]}
    assert Fount.Writer.swimlanes(model) == %{"A" => [%{scene_id: first.id, beat: "Arrival", ordinal: 1}]}
    assert Fount.Writer.scene_numbers(model) == {:ok, %{first.id => "1", second.id => "2", third.id => "3"}}
    {:ok, omitted} = Screenplay.apply(model, Fount.Edit.omit_scene(second.id))
    assert Fount.Writer.scene_numbers(omitted) == {:ok, %{first.id => "1", third.id => "2"}}
    assert Fount.Writer.location_groups(omitted) == %{"HOUSE" => [first.id], "ROAD" => [third.id]}
    assert Fount.Writer.word_counts(model, first.id) == {:ok, %{action: 2, dialogue: 0}}
    assert Fount.Writer.word_counts(omitted, second.id) == {:ok, %{action: 0, dialogue: 0}}
    assert Fount.Writer.word_counts(omitted, second.id, include_omitted: true) == {:ok, %{action: 2, dialogue: 0}}
  end

  test "scene numbering preserves literal locked numbers and exposes collision" do
    model =
      Screenplay.new(
        scenes: [
          %{heading: "INT. A - DAY", elements: []},
          %{heading: "INT. B - DAY", elements: []}
        ]
      )

    [first, second] = model.ir.scenes
    locked = %{second | number: "1"}
    model = %{model | ir: %{model.ir | scenes: [first, locked]}}
    assert {:error, {:scene_number_conflict, "1"}} = Fount.Writer.scene_numbers(model)
  end

  test "inserted scenes between locked numbers receive alphanumeric display suffixes" do
    model =
      Screenplay.new(
        scenes: [
          %{heading: "INT. A - DAY", number: "24", elements: []},
          %{heading: "INT. INSERT ONE - DAY", elements: []},
          %{heading: "INT. INSERT TWO - DAY", elements: []},
          %{heading: "INT. B - DAY", number: "25", elements: []}
        ]
      )

    [first, second, third, fourth] = model.ir.scenes

    assert Fount.Writer.scene_numbers(model) ==
             {:ok,
              %{
                first.id => "24",
                second.id => "24A",
                third.id => "24B",
                fourth.id => "25"
              }}
  end
end
