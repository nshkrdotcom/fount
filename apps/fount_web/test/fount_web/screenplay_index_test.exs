defmodule FountWeb.ScreenplayIndexTest do
  use ExUnit.Case, async: true

  alias Fount.Analyzers.{Characters, Dialogue, Locations}
  alias FountWeb.ScreenplayIndex

  defp model do
    """
    INT. CAFÉ - NIGHT

    MARA
    (quietly)
    One two three.

    OWEN ^
    Four five.

    EXT. PLATFORM - DAY

    MARA
    Six seven eight nine.
    """
    |> Fount.parse!()
    |> Fount.Screenplay.from_document(cast_resolution: :literal_cues)
  end

  defp analyzer_subject(screenplay),
    do: %{
      id: screenplay.id,
      revision: screenplay.revision,
      ir: screenplay.ir,
      index: screenplay.index
    }

  test "projects deterministic Core analyzer values and literal cue identity limits" do
    screenplay = model()
    index = ScreenplayIndex.build(screenplay)
    subject = analyzer_subject(screenplay)

    {:ok, character_annotations} = Characters.analyze(subject, [])
    {:ok, dialogue_annotations} = Dialogue.analyze(subject, [])
    {:ok, location_annotations} = Locations.analyze(subject, [])

    assert Enum.map(index.characters, &{&1.name, &1.cue_count}) ==
             character_annotations
             |> Enum.map(&{&1.value.name, &1.value.cue_count})
             |> Enum.sort_by(fn {name, count} -> {-count, name} end)

    assert Enum.map(
             index.dialogue,
             &Map.take(&1, [:character, :words, :characters, :parentheticals, :dual?, :side])
           ) ==
             Enum.map(dialogue_annotations, & &1.value)

    assert Enum.sort(Enum.map(index.locations, & &1.location)) ==
             location_annotations |> Enum.map(& &1.value.location) |> Enum.uniq() |> Enum.sort()

    assert Enum.all?(
             index.characters,
             &String.contains?(&1.identity_note, "does not prove a cast entity relationship")
           )

    assert Enum.all?(index.characters, &(&1.analyzer_kind == :character_cue_summary))
  end

  test "character filter is bounded to the selected model and estimates distinguish zero from derived values" do
    screenplay = model()
    filtered = ScreenplayIndex.build(screenplay, character_filter: "mara")
    assert Enum.map(filtered.characters, & &1.name) == ["MARA"]
    assert filtered.estimates.pages.value > 0
    assert filtered.estimates.pages.label =~ "derived reading approximation"
    assert filtered.estimates.duration.value > 0

    empty = ScreenplayIndex.build(Fount.Screenplay.new())
    assert empty.estimates.pages.value == 0
    assert empty.estimates.duration.value == 0
    assert empty.estimates.duration.label =~ "0 minutes"

    unknown = ScreenplayIndex.estimates(%{ir: %{elements: nil}})
    assert unknown.duration.value == nil
    assert unknown.duration.label =~ "unknown"

    assert Enum.map(ScreenplayIndex.scene_index(screenplay), & &1.id) ==
             Enum.map(screenplay.ir.scenes, & &1.id)
  end
end
