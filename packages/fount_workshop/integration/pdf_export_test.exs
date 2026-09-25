defmodule FountWorkshop.PDFExportTest do
  use ExUnit.Case, async: false

  alias FountWorkshop.Export.PDF

  test "exports a letter-size readable PDF with embedded Courier Prime and hidden notes" do
    source = """
    Title: The Test Script
    Credit: Written by
    Author: A Writer

    INT. ROOM - DAY

    MARA
    Keep the light on.

    [[PRIVATE RESEARCH NOTE]]

    DAN
    We have to leave.

    MARA ^
    Then go.
    """

    doc = Fount.parse!(source)
    root = Path.join(System.tmp_dir!(), "fount-pdf-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    output = Path.join(root, "draft.pdf")

    assert {:ok, report} = PDF.export(doc, output)
    assert report.pages >= 2
    assert report.page_size == :us_letter
    assert report.courier_prime?
    assert report.blank_pages == []
    assert report.source_revision == doc.revision.id
    assert File.read!(output) |> String.starts_with?("%PDF-")

    {info, 0} = System.cmd("pdfinfo", [output])
    assert String.contains?(info, "Page size:       612 x 792 pts (letter)")

    {fonts, 0} = System.cmd("pdffonts", [output])
    assert String.contains?(fonts, "CourierPrime")

    {text, 0} = System.cmd("pdftotext", [output, "-"])
    assert String.contains?(text, "Keep the light on.")
    assert String.contains?(text, "We have to leave.")
    refute String.contains?(text, "PRIVATE RESEARCH NOTE")
  end

  test "a long draft paginates and preserves text after an explicit page break" do
    action =
      Enum.map_join(1..90, "\n", fn number -> "Line #{number}: The crew crosses the room." end)

    source =
      "INT. STUDIO - DAY\n\n" <>
        action <>
        "\n\n===\n\nEXT. STREET - NIGHT\n\nMARA\nThe café is closed."

    doc = Fount.parse!(source)
    root = Path.join(System.tmp_dir!(), "fount-pages-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    output = Path.join(root, "pages.pdf")

    assert {:ok, report} = PDF.export(doc, output)
    assert report.pages >= 3
    assert report.source_revision == doc.revision.id

    {text, 0} = System.cmd("pdftotext", [output, "-"])
    assert String.contains?(text, "Line 90: The crew crosses the room.")
    assert String.contains?(text, "The café is closed.")
  end

  test "canonical omission excludes a scene from a readable PDF" do
    model =
      Fount.Screenplay.new(
        scenes: [
          %{
            heading: "INT. CUT ROOM - DAY",
            elements: [%{type: :action, text: "Omitted sentinel."}]
          },
          %{heading: "EXT. ROAD - DAY", elements: [%{type: :action, text: "Visible sentinel."}]}
        ]
      )

    scene = hd(model.ir.scenes)
    {:ok, model} = Fount.Screenplay.apply(model, Fount.Edit.omit_scene(scene.id))
    root = Path.join(System.tmp_dir!(), "fount-omission-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    output = Path.join(root, "omitted.pdf")

    assert {:ok, report} = PDF.export(model, output)
    assert report.source_revision == model.revision.id
    {text, 0} = System.cmd("pdftotext", [output, "-"])
    refute String.contains?(text, "Omitted sentinel")
    assert String.contains?(text, "Visible sentinel")
  end

  test "A4 output uses requested print settings and a distinct settings hash" do
    doc = Fount.parse!("Title: Example\n\nINT. ROOM - DAY\n\nA line.")
    root = Path.join(System.tmp_dir!(), "fount-a4-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)

    assert {:ok, letter} = PDF.export(doc, Path.join(root, "letter.pdf"))
    assert {:ok, a4} =
             PDF.export(doc, Path.join(root, "a4.pdf"),
               print_profile: "a4",
               print_title_page: false
             )

    assert a4.page_size == :a4
    assert a4.settings_sha256 != letter.settings_sha256
    assert a4.settings["print_profile"] == "a4"
    assert a4.settings["print_title_page"] == false
  end
end
