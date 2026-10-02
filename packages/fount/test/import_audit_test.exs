defmodule Fount.ImportAuditTest do
  use ExUnit.Case, async: true

  alias Fount.ID
  alias Fount.Screenplay
  alias Fount.Semantics.SourceInventory

  test "parser audit distinguishes repeated cues from identities and flags printed-text ambiguity" do
    source =
      "Title: Audit\r\n\r\nINT. ROOM - DAY\r\n\r\nMIRA\r\nHello.\r\n\r\nMIRA\r\nAgain.\r\n\r\nA charging document reads:\r\n\r\nCOUNT ONE:\r\nVIOLENT INTERFERENCE.\r\n"

    screenplay = source |> Fount.parse!() |> Screenplay.from_document(cast_resolution: :manual)
    audit = SourceInventory.build(screenplay).import_audit
    assert audit.cue_occurrences == 3
    assert audit.distinct_cue_spellings == 2
    assert audit.repeated_cue_groups["MIRA"] == 2
    assert audit.semantic_confidence == "unknown"
    assert [%{literal: "COUNT ONE:", source_span: %{line_start: 13}}] = audit.suspected_document_cues
    assert Enum.all?(audit.decisions, &is_binary(&1.rule))
    assert Enum.count(audit.decisions, &(&1.rule == "uppercase_letters_after_blank_before_nonblank")) == 3
    assert audit.source_sha256 == ID.hash(source)
    assert Screenplay.to_fountain(screenplay) == source
    assert screenplay.cast == %{}
  end

  test "FDX audit separates original artifact identity from decoded visible-source ranges" do
    xml =
      ~s(<FinalDraft DocumentType="Script" Version="1"><Content><Paragraph Type="Scene Heading"><Text>INT. ROOM - DAY</Text></Paragraph><Paragraph Type="Character"><Text>MIRA</Text></Paragraph><Paragraph Type="Dialogue"><Text>Hello.</Text></Paragraph></Content></FinalDraft>)

    assert {:ok, screenplay, _} = Screenplay.from_fdx(xml)
    audit = SourceInventory.build(screenplay).import_audit
    assert audit.source_format == "fdx"
    assert audit.source_sha256 == ID.hash(xml)
    assert audit.span_basis == "visible_fountain_revision"
    assert audit.visible_source_sha256 == ID.hash(Screenplay.to_fountain(screenplay))
    assert Enum.all?(audit.decisions, &(&1.rule == "fdx_decode_then_fountain_syntax"))
    assert {:ok, exported} = Screenplay.to_fdx(screenplay)
    assert exported.data == xml
  end
end
