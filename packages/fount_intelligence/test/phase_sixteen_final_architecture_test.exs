defmodule Fount.Intelligence.PhaseSixteenFinalArchitectureTest do
  use ExUnit.Case, async: true
  alias Fount.Intelligence.Runner.Architecture

  @root Path.expand("../../..", __DIR__)
  @packages ~w(fount fount_observe fount_intelligence fount_workshop fount_run)
  @removed ~w(fount_probe fount_analysis fount_semantics fount_temporal fount_reader fount_diagnose fount_playbooks)

  test "final source architecture has the five current libraries and no removed package residue" do
    actual =
      @root
      |> Path.join("packages/*/mix.exs")
      |> Path.wildcard()
      |> Enum.map(&(Path.dirname(&1) |> Path.basename()))
      |> Enum.sort()

    assert actual == Enum.sort(@packages)
    refute Enum.any?(@removed, &File.exists?(Path.join([@root, "packages", &1])))

    report = Architecture.check(@root, source_only: true)
    assert report["status"] == "pass", inspect(report["violations"], pretty: true)
  end

  test "production source has no Probe module or superseded physical package dependency" do
    sources = Path.wildcard(Path.join(@root, "packages/*/lib/**/*.ex"))
    text = Enum.map_join(sources, "\n", &File.read!/1)

    refute String.contains?(text, "FountProbe")
    refute String.contains?(text, "fount_probe")

    for name <- tl(@removed) do
      refute String.contains?(text, name), name
    end
  end
end