defmodule Fount.Fountain.ScannerTest do
  use ExUnit.Case, async: true

  alias Fount.Fountain.Scanner
  alias Fount.Source.Line

  test "preserves mixed line terminators and exact bytes" do
    source = "a\r\nb\nc\rd"
    scanned = Scanner.scan(source)

    assert scanned.newline_style == :mixed
    assert IO.iodata_to_binary(Enum.map(scanned.lines, &Line.raw/1)) == source
    assert Enum.map(scanned.lines, & &1.eol) == ["\r\n", "\n", "\r", ""]
  end

  test "does not invent a trailing blank line" do
    scanned = Scanner.scan("a\n")
    assert length(scanned.lines) == 1
    assert hd(scanned.lines).content == "a"
    assert hd(scanned.lines).eol == "\n"
  end

  test "keeps whitespace-only lines distinct from structural empty lines" do
    [empty, spaces] = Scanner.scan("\n  ").lines
    assert Line.empty?(empty)
    refute Line.empty?(spaces)
    assert Line.whitespace_only?(spaces)
  end
end
