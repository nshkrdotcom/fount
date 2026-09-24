defmodule Fount.Adapter.FDXTest do
  use ExUnit.Case, async: true

  alias Fount.Adapter.FDX

  test "imports basic FDX into editable canonical Fountain" do
    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <FinalDraft DocumentType="Script" Template="No" Version="2">
      <Content>
        <Paragraph Type="Scene Heading"><SceneProperties Number="7"/><Text>INT. KITCHEN - NIGHT</Text></Paragraph>
        <Paragraph Type="Action"><Text>Mara enters.</Text></Paragraph>
        <Paragraph Type="Character"><Text>MARA</Text></Paragraph>
        <Paragraph Type="Dialogue"><Text>Hello.</Text></Paragraph>
      </Content>
    </FinalDraft>
    """

    assert {:ok, result} = FDX.decode(xml)
    assert length(result.document.ir.scenes) == 1
    assert hd(Fount.elements(result.document, :dialogue)).text == "Hello."
  end

  test "exports spec-script structure as parseable FDX" do
    doc = Fount.parse!("INT. ROOM - DAY\n\nMARA\nHello.\n")
    assert {:ok, result} = FDX.export(doc)
    assert String.contains?(result.data, "FinalDraft")
    assert {:ok, imported} = FDX.decode(result.data)
    assert hd(Fount.elements(imported.document, :dialogue)).text == "Hello."
  end

  test "imports unconventional headings and mixed-case cues as their FDX types" do
    xml = """
    <FinalDraft><Content>
      <Paragraph Type="Scene Heading"><Text>FLASHBACK - ROOM</Text></Paragraph>
      <Paragraph Type="Character"><Text>McKay</Text></Paragraph>
      <Paragraph Type="Dialogue"><Text>Fish &amp; chips.</Text></Paragraph>
    </Content></FinalDraft>
    """

    assert {:ok, result} = FDX.decode(xml)
    assert hd(Fount.elements(result.document, :scene_heading)).text == "FLASHBACK - ROOM"
    assert hd(Fount.elements(result.document, :character)).text == "McKay"
    assert hd(Fount.elements(result.document, :dialogue)).text == "Fish & chips."
    assert String.contains?(Fount.render(result.document), ".FLASHBACK - ROOM")
    assert String.contains?(Fount.render(result.document), "@McKay")
  end

  test "reports unsupported production metadata and styling during import" do
    xml = """
    <FinalDraft RevisionID="rev-1">
      <Content>
        <Paragraph Type="Action"><Text Style="Highlight">A marked line.</Text></Paragraph>
      </Content>
      <LockedPages />
      <TagData />
    </FinalDraft>
    """

    assert {:ok, result} = FDX.decode(xml)
    assert hd(Fount.elements(result.document, :action)).text == "A marked line."
    assert Enum.any?(result.losses, &String.contains?(&1, "revision metadata"))
    assert Enum.any?(result.losses, &String.contains?(&1, "locked-page"))
    assert Enum.any?(result.losses, &String.contains?(&1, "production tags"))
    assert Enum.any?(result.losses, &String.contains?(&1, "Highlight"))
  end
end
