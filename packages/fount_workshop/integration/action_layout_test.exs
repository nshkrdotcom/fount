defmodule FountWorkshop.ActionLayoutTest do
  use ExUnit.Case, async: false

  test "action line counts come from verified rendered PDF lines" do
    model = Fount.Screenplay.new(scenes: [%{heading: "INT. ROOM - DAY", elements: [%{type: :action, text: "Mara opens the heavy wooden door and steps through into the empty room."}]}])
    root = Path.join(System.tmp_dir!(), "fount-action-layout-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    assert {:ok, pdf} = FountWorkshop.Export.PDF.export(model, Path.join(root, "draft.pdf"))
    {:ok, units} = FountProbe.Projection.select(model, %{"whole_screenplay" => true})
    action = Enum.filter(units, &(&1["type"] == "action"))
    id = Fount.ID.v4()
    payload = %{"id" => id, "tool" => "layout_compare", "status" => "complete", "screenplay_id" => model.id, "primary_revision_id" => model.revision.id, "data" => %{"candidate_pdf" => Fount.Screenplay.Model.plain(pdf)}}
    reader = fn ^id -> {:ok, %{"id" => id, "payload" => payload}} end

    assert {:ok, measured} = FountProbe.Action.Layout.measure(model, action, id, reader)
    assert measured["printed_lines"] >= 1
    assert measured["layout_status"] == "measured_from_pdf"
    assert length(measured["line_regions"]) == 1
    assert hd(measured["line_regions"])["line_count"] == measured["printed_lines"]

    forged = put_in(payload, ["data", "candidate_pdf", "sha256"], "wrong")
    bad_reader = fn ^id -> {:ok, %{"id" => id, "payload" => forged}} end
    assert {:error, :pdf_hash_mismatch} = FountProbe.Action.Layout.measure(model, action, id, bad_reader)
  end
end
