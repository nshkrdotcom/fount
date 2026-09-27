defmodule Fount.Intelligence.StoryWorldArchitectureTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.Runner.Architecture

  test "StoryWorld pure source rejects provider, repository, filesystem, clock, and random shortcuts" do
    samples = [
      "defmodule Fount.Intelligence.StoryWorld.Bad do\n def run, do: SystemOneSDK.evaluate(:x, %{}, [])\nend",
      "defmodule Fount.Intelligence.StoryWorld.Bad do\n def run, do: Inference.complete(:x, \"x\")\nend",
      "defmodule Fount.Intelligence.StoryWorld.Bad do\n def run, do: Fount.Repo.all(:x)\nend",
      "defmodule Fount.Intelligence.StoryWorld.Bad do\n def run, do: File.read!(\"x\")\nend",
      "defmodule Fount.Intelligence.StoryWorld.Bad do\n def run, do: DateTime.utc_now()\nend",
      "defmodule Fount.Intelligence.StoryWorld.Bad do\n def run, do: Fount.ID.v4()\nend"
    ]

    for source <- samples do
      assert Architecture.source_violations(
               source,
               "packages/fount_intelligence/lib/fount/intelligence/story_world/bad.ex"
             ) != []
    end
  end
end
