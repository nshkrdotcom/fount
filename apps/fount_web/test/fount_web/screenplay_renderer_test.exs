defmodule FountWeb.ScreenplayRendererTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  defmodule Harness do
    use Phoenix.Component
    attr :screenplay, :any, required: true

    def render(assigns) do
      ~H"""
      <FountWeb.Components.ScreenplayRenderer.screenplay screenplay={@screenplay} />
      """
    end
  end

  defp model(source) do
    source
    |> Fount.parse!()
    |> Fount.Screenplay.from_document(cast_resolution: :literal_cues)
  end

  test "renders title, scene anchors, dual dialogue, notes, Unicode and escaped source text" do
    screenplay =
      model("""
      Title: Viewer <Draft>
      Author: Zoë

      # ACT ONE
      INT. CAFÉ - NIGHT #7#

      [[private <script>alert(1)</script> note]]

      MARA
      (quietly)
      Left side — café.

      OWEN ^
      Right side.

      >CUT TO:

      >CENTERED BEAT<

      ~A lyric line

      = a synopsis

      ===

      /* retired beat */
      """)

    html = render_component(&Harness.render/1, %{screenplay: screenplay})
    [scene] = screenplay.ir.scenes

    assert html =~ "Viewer &lt;Draft&gt;"
    assert html =~ "Zoë"
    assert html =~ ~s(id="scene-#{scene.id}")
    assert html =~ "screenplay-dual"
    assert html =~ "private &lt;script&gt;alert(1)&lt;/script&gt; note"
    refute html =~ "<script>alert(1)</script>"
    assert html =~ "CUT TO:"
    for css <- ~w(action character dialogue parenthetical transition centered lyric section synopsis note boneyard page-break) do
      assert html =~ "screenplay-element--#{css}"
    end

    unknown = Fount.Screenplay.new(body: [%{type: :unknown, text: "future element"}])
    unknown_html = render_component(&Harness.render/1, %{screenplay: unknown})
    assert unknown_html =~ "Unsupported element type: unknown"
    assert unknown_html =~ "future element"
  end

  test "empty and long screenplay content stays visible" do
    empty = Fount.Screenplay.new()
    assert render_component(&Harness.render/1, %{screenplay: empty}) =~ "Empty screenplay"

    long_text = String.duplicate("long block Ω ", 800)
    long = model("INT. ROOM - DAY\n\n#{long_text}\n")
    html = render_component(&Harness.render/1, %{screenplay: long})
    assert html =~ "long block Ω"
    assert html =~ String.slice(long_text, -60, 60)
  end
end
