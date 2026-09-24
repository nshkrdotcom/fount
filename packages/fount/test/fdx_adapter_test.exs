defmodule Fount.Adapter.FDXTest do
  use ExUnit.Case, async: true

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

    assert {:ok, result} = Fount.Adapter.FDX.decode(xml)
    assert length(result.document.ir.scenes) == 1
    assert hd(Fount.elements(result.document, :dialogue)).text == "Hello."
  end

  test "exports spec-script structure as parseable FDX" do
    doc = Fount.parse!("INT. ROOM - DAY\n\nMARA\nHello.\n")
    assert {:ok, result} = Fount.Adapter.FDX.export(doc)
    assert String.contains?(result.data, "FinalDraft")
    assert {:ok, imported} = Fount.Adapter.FDX.decode(result.data)
    assert hd(Fount.elements(imported.document, :dialogue)).text == "Hello."
  end
end
