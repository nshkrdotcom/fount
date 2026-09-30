defmodule FountWeb.DiffViewerTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias FountWeb.Components.DiffViewer

  defmodule Harness do
    use Phoenix.Component
    attr :before, :any, required: true
    attr :after, :any, required: true
    attr :mode, :string, default: "unified"

    def render(assigns) do
      ~H"""
      <FountWeb.Components.DiffViewer.diff
        before={@before}
        after={@after}
        before_label="Run base"
        after_label="Candidate"
        mode={@mode}
      />
      """
    end
  end

  defp base do
    """
    INT. ROOM - DAY

    Old action.

    EXT. STREET - NIGHT

    Second action.
    """
    |> Fount.parse!()
    |> Fount.Screenplay.from_document(cast_resolution: :literal_cues)
  end

  test "change, move and unchanged cases retain revision identities and textual labels" do
    base = base()
    [action | _] = Fount.Query.elements(base, :action)
    {:ok, changed} = Fount.Screenplay.apply(base, Fount.Edit.replace_text(action.id, "New action."))
    assert {:ok, payload} = DiffViewer.diff_payload(base, changed)
    assert Enum.any?(payload.entries, &(&1.change == :changed and &1.id == action.id))

    [first, second] = base.ir.scenes
    {:ok, moved} = Fount.Screenplay.apply(base, Fount.Edit.move_scene(first.id, second.id))
    assert {:ok, moved_payload} = DiffViewer.diff_payload(base, moved)
    assert Enum.any?(moved_payload.entries, &(&1.change == :moved and &1.id == first.id))

    scene = hd(base.ir.scenes)
    insert = %{
      "kind" => "insert_elements",
      "target" => %{"kind" => "scene", "id" => scene.id},
      "value" => %{
        "position" => "end",
        "anchor_id" => nil,
        "elements" => [
          %{"local_id" => "new:diff-beat", "type" => "action", "text" => "Inserted beat.", "attrs" => %{}}
        ]
      }
    }
    assert {:ok, inserted, _} = Fount.Screenplay.apply(base, [insert])
    assert {:ok, inserted_payload} = DiffViewer.diff_payload(base, inserted)
    assert Enum.any?(inserted_payload.entries, &(&1.change == :added))

    assert {:ok, removed, _} =
             Fount.Screenplay.apply(base, [%{"kind" => "delete_elements", "value" => %{"ids" => [action.id]}}])
    assert {:ok, removed_payload} = DiffViewer.diff_payload(base, removed)
    assert Enum.any?(removed_payload.entries, &(&1.change == :removed and &1.id == action.id))

    assert {:ok, %{entries: []}} = DiffViewer.diff_payload(base, base)

    html = render_component(&Harness.render/1, %{before: base, after: changed, mode: "side-by-side"})
    assert html =~ base.revision.id
    assert html =~ changed.revision.id
    assert html =~ "Changed"
    assert html =~ "diff-viewer--side-by-side"
  end

  test "mismatched screenplay IDs are rejected instead of diffed" do
    left = base()
    right = base()
    assert {:error, :different_screenplay} = DiffViewer.diff_payload(left, right)
    html = render_component(&Harness.render/1, %{before: left, after: right})
    assert html =~ "different screenplay identities"
  end
end
