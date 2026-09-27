defmodule Fount.Intelligence.ArchitectureTest do
  use ExUnit.Case, async: true
  alias Fount.Intelligence.Runner.Architecture

  test "aliases, imports, captures, structs and dynamic dispatch cannot conceal a core-to-shell edge" do
    bad = [
      "alias File, as: Disk\ndef run, do: Disk.read!(\"private\")",
      "import System, only: [get_env: 1]\ndef run, do: get_env(\"SECRET\")",
      "def run, do: &Fount.Intelligence.Acquisition.Measurements.evaluate/4",
      "def run, do: %FountWorkshop.Store{repo: nil}",
      "def run(m), do: apply(m, :execute, [])",
      "def run(m), do: m.execute()",
      "def run, do: :erlang.system_time()"
    ]
    for body <- bad do
      source = "defmodule Fount.Intelligence.Reader.Bad do\n#{body}\nend"
      assert Architecture.source_violations(source, "packages/fount_intelligence/lib/bad.ex") != [], body
    end
  end

  test "pure leaf contracts and deterministic transformations remain usable" do
    source = """
    defmodule Fount.Intelligence.Reader.Example do
      alias Fount.Observe.Distribution, as: D
      def run(%D{values: values}), do: Enum.sort(values)
    end
    """
    assert Architecture.source_violations(source, "packages/fount_intelligence/lib/example.ex") == []
  end

  test "provider-native structs cannot move into Intelligence or an Observe leaf" do
    for file <- ["packages/fount_intelligence/lib/bad.ex", "packages/fount_observe/lib/fount/observe/distribution.ex"] do
      source = "defmodule Bad do\ndef run(x), do: SystemOneSDK.evaluate(x, %{}, [])\nend"
      assert Enum.any?(Architecture.source_violations(source, file), &(&1["rule"] == "native_provider_boundary"))
    end
  end
  test "nested modules keep their owning namespace and restore the parent's aliases" do
    source = """
    defmodule Fount.Intelligence.Reader.Outer do
      alias File, as: Disk
      defmodule Inner do
        def read, do: System.get_env("SECRET")
      end
      def read, do: Disk.read!("private")
    end
    """
    violations = Architecture.source_violations(source, "packages/fount_intelligence/lib/nested.ex")
    assert Enum.any?(violations, &String.contains?(&1["dependency"], "System.get_env"))
    assert Enum.any?(violations, &String.contains?(&1["dependency"], "File.read!"))
  end

  test "an explicit current-module capture is deterministic static dispatch" do
    source = """
    defmodule Fount.Intelligence.Reader.Local do
      def pair, do: &__MODULE__.run/1
      def run(value), do: value
    end
    """
    assert Architecture.source_violations(source, "packages/fount_intelligence/lib/local.ex") == []
  end

end
