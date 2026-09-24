defmodule Fount.WritingContractsTest do
  use ExUnit.Case, async: true
  alias Fount.Writing.{CanonicalJSON, LocalReferences, UTF8Span}

  test "spans are bytes, cannot split codepoints, and require exact excerpts" do
    assert {:ok, "é"} = UTF8Span.extract("café.", {3, 5})
    assert {:error, :split_utf8_codepoint} = UTF8Span.extract("café.", {3, 4})
    assert {:error, :excerpt_mismatch} = UTF8Span.verify("café.", [3, 5], "e")
    assert {:error, :invalid_span} = UTF8Span.extract("café.", {5, 5})
  end

  test "relocation detects overlap and does not reuse old pin offsets" do
    assert {:ok, {7, 11}} = UTF8Span.relocate("Before hold after", "hold")
    assert {:error, :ambiguous_protected_text} = UTF8Span.relocate("aaaa", "aaa")
    assert {:error, :protected_text_changed} = UTF8Span.relocate("changed", "hold")
  end

  test "canonical JSON sorts objects but retains array order" do
    assert CanonicalJSON.encode!(%{"z" => 1, "a" => %{"c" => 3, "b" => 2}}) ==
             ~s({"a":{"b":2,"c":3},"z":1})
    refute CanonicalJSON.hash([1, 2]) == CanonicalJSON.hash([2, 1])
    assert {:error, :object_keys_must_be_strings} = CanonicalJSON.encode(%{bad: 1})
  end

  test "local references allocate once and prose remains literal" do
    uuid = "f8136c1a-fb18-4c24-bd41-c2cb602c98a0"
    input = [
      %{"local_id" => "new:mara", "name" => "Mara"},
      %{"character_id" => "new:mara", "text" => "new:literal-dialogue"}
    ]

    assert {:ok, [character, line], %{"new:mara" => ^uuid}} =
             LocalReferences.compile(input, uuid: fn -> uuid end)
    assert character["id"] == uuid
    assert line["character_id"] == uuid
    assert line["text"] == "new:literal-dialogue"
  end

  test "duplicate declarations and undeclared references fail" do
    assert {:error, {:duplicate_local_ids, ["new:a"]}} =
             LocalReferences.compile([%{"local_id" => "new:a"}, %{"local_id" => "new:a"}])
    assert {:error, {:undeclared_local_reference, "new:missing"}} =
             LocalReferences.compile(%{"anchor_id" => "new:missing"})
  end
end
