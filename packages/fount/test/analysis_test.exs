defmodule Fount.AnalysisTest do
  use ExUnit.Case, async: true

  test "reports, cue entities, and annotations remain distinct from screenplay truth" do
    source = "INT. LAB - NIGHT\n\nMARA\nHello there.\n\nDAN\nHi.\n\nMARA\nAgain.\n"
    doc = Fount.parse!(source)

    summary = Fount.Report.summary(doc)
    assert summary.scenes == 1
    assert summary.dialogue_turns == 3
    assert Enum.find(summary.characters, &(&1.name == "MARA")).cue_count == 2

    {:ok, doc} = Fount.analyze(doc, Fount.Analyzers.Locations)
    {:ok, doc} = Fount.analyze(doc, Fount.Analyzers.Dialogue)
    {:ok, doc} = Fount.analyze(doc, Fount.Analyzers.CharacterEntities)

    assert length(Fount.Annotations.by_kind(doc.annotations, :scene_heading_parts)) == 1
    assert length(Fount.Annotations.by_kind(doc.annotations, :dialogue_turn_metrics)) == 3
    assert length(Fount.Annotations.by_kind(doc.annotations, :character_entity)) == 2
    assert length(doc.ir.elements) == length(Fount.elements(doc))
  end

  test "caller time terms classify headings without changing source" do
    source = "INT. CAFÉ - NUIT\n\nMARA\nBonsoir.\n"
    doc = Fount.parse!(source)
    heading = hd(Fount.elements(doc, :scene_heading))
    assert Fount.SceneHeading.parse(heading.text).time == nil
    assert Fount.SceneHeading.parse(heading.text, extra_time_terms: ["nuit"]).time == "NUIT"
    assert {:ok, analyzed} = Fount.analyze(doc, Fount.Analyzers.Locations, extra_time_terms: ["NUIT"])
    [annotation] = Fount.Annotations.by_kind(analyzed.annotations, :scene_heading_parts)
    assert annotation.value.time == "NUIT"
    assert Fount.render(analyzed) == source
  end
end
