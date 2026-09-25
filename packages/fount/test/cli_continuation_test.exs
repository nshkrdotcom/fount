defmodule Fount.CLIContinuationTest do
  use ExUnit.Case, async: true

  test "unknown flags and duplicate scalar flags fail before any side effect" do
    assert {:error, _} = Fount.CLI.Support.parse(["--imaginary"], key: :string)
    assert {:error, _} = Fount.CLI.Support.parse(["--key", "a", "--key", "b"], key: :string)
    assert {:ok, [help: true], []} = Fount.CLI.Support.parse(["--help"], key: :string)
  end

  test "comma-separated identities are nonempty and unique" do
    assert {:ok, ["one", "two"]} = Fount.CLI.Support.ids("one,two")
    assert {:error, _} = Fount.CLI.Support.ids("one,one")
    assert {:error, _} = Fount.CLI.Support.ids("")
  end
end
