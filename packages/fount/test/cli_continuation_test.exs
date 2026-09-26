defmodule Fount.CLIContinuationTest do
  alias Fount.CLI.Support
  use ExUnit.Case, async: true

  test "unknown flags and duplicate scalar flags fail before any side effect" do
    assert {:error, _} = Support.parse(["--imaginary"], key: :string)
    assert {:error, _} = Support.parse(["--key", "a", "--key", "b"], key: :string)
    assert {:ok, [help: true], []} = Support.parse(["--help"], key: :string)
  end

  test "comma-separated identities are nonempty and unique" do
    assert {:ok, ["one", "two"]} = Support.ids("one,two")
    assert {:error, _} = Support.ids("one,one")
    assert {:error, _} = Support.ids("")
  end
end
