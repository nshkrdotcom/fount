defmodule Fount.Intelligence.PhaseSixWebHostArchitectureTest do
  use ExUnit.Case, async: true
  alias Fount.Intelligence.Runner.Architecture

  @root Path.expand("../../..", __DIR__)

  test "Phase 06 keeps five libraries plus exactly one external Phoenix host" do
    assert File.regular?(Path.join(@root, "apps/fount_web/mix.exs"))
    refute File.exists?(Path.join(@root, "packages/fount_web"))

    report = Architecture.check(@root, source_only: true)
    assert report["status"] == "pass", inspect(report["violations"], pretty: true)
  end

  test "library package declarations remain Phoenix-free" do
    for path <- Path.wildcard(Path.join(@root, "packages/*/mix.exs")) do
      source = File.read!(path)
      refute source =~ "{:phoenix,"
      refute source =~ "{:phoenix_live_view,"
      refute source =~ "{:phoenix_ecto,"
    end
  end
end
