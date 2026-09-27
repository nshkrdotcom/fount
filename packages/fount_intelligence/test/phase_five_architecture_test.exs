defmodule Fount.Intelligence.PhaseFiveArchitectureTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.Runner.Architecture

  test "Diagnosis pure source rejects acquisition, providers, persistence, filesystem, clock, and random effects" do
    samples = [
      "defmodule Fount.Intelligence.Diagnosis.Bad do\n def run, do: Fount.Observe.evaluate(nil, [], [])\nend",
      "defmodule Fount.Intelligence.Diagnosis.Bad do\n def run, do: SystemOneSDK.evaluate(:x, %{}, [])\nend",
      "defmodule Fount.Intelligence.Diagnosis.Bad do\n def run, do: Fount.Repo.all(:x)\nend",
      "defmodule Fount.Intelligence.Diagnosis.Bad do\n def run, do: File.read!(\"x\")\nend",
      "defmodule Fount.Intelligence.Diagnosis.Bad do\n def run, do: DateTime.utc_now()\nend",
      "defmodule Fount.Intelligence.Diagnosis.Bad do\n def run, do: Fount.ID.v4()\nend"
    ]

    for source <- samples do
      assert Architecture.source_violations(
               source,
               "packages/fount_intelligence/lib/fount/intelligence/diagnosis/bad.ex"
             ) != []
    end
  end
end
