defmodule FountWeb.Phase05AuthoringContractTest do
  use ExUnit.Case, async: true

  test "E01-E07 host contract exposes no browser body cache or direct Workshop generation path" do
    js = File.read!(Path.expand("../../assets/js/app.js", __DIR__))
    authoring = File.read!(Path.expand("../../lib/fount_web/authoring.ex", __DIR__))
    live = File.read!(Path.expand("../../lib/fount_web/live/editor_live.ex", __DIR__))

    refute js =~ "localStorage"
    [_, editor_js] = String.split(js, "const AuthoringEditor =", parts: 2)
    refute editor_js =~ "sessionStorage"
    assert js =~ "setTimeout(() => this.preview(), 300)"
    assert js =~ "compositionstart"
    assert js =~ "beforeunload"
    assert authoring =~ "FountWeb.Launch.create_from_candidate"
    refute authoring =~ "FountWorkshop."
    assert live =~ "Fount.Screenplay.undo"
    assert live =~ "Fount.Screenplay.redo"
    assert live =~ "Saving a proposed change still does not replace the current screenplay"
  end

  test "authoring limits are explicitly configured" do
    config = Application.get_env(:fount_web, :authoring)
    assert config[:autosave_ms] == 60_000
    assert config[:history_limit] == 30
    assert config[:draft_limit] == 12
    assert config[:max_source_bytes] == 1_048_576
  end
end
