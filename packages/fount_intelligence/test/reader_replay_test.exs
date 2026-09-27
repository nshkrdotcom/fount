defmodule Fount.Intelligence.ReaderReplayTest do
  use ExUnit.Case, async: true
  alias Fount.Intelligence.Reader.Reveal
  alias Fount.Intelligence.StoryWorld.Records

  test "frozen checkpoint replay is deterministic and a changed suffix cannot alter an earlier prefix" do
    prefix = [%{"point" => 0, "probability" => 0.1}, %{"point" => 1, "probability" => 0.9}]
    first = prefix ++ [%{"point" => 2, "probability" => 0.2}]
    revised = prefix ++ [%{"point" => 2, "probability" => 0.95}]
    assert Reveal.boundary(Enum.take(first, 2)) == Reveal.boundary(Enum.take(revised, 2))
    assert Reveal.boundary(first) == Reveal.boundary(first)
    assert {:ok, %{"drops" => [2]}} = Reveal.boundary(first)
    assert {:ok, %{"drops" => []}} = Reveal.boundary(revised)
    assert {:ok, %{"status" => "incomplete", "first_crossing" => nil}} =
      Reveal.boundary([%{"point" => 0, "probability" => nil}])
  end

  test "proposed records cannot cite adjacent or uninspected source" do
    unit = %{"evidence_id" => "inspected"}
    object = %{"summary" => "A choice", "records" => [%{"id" => "choice", "kind" => "events",
      "claim" => "Mara leaves", "subjects" => [], "evidence_ids" => ["inspected"], "uncertainty" => ""}]}
    assert :ok = Records.validate(object, [unit], ["events"])
    forged = put_in(object, ["records", Access.at(0), "evidence_ids"], ["adjacent"])
    assert {:error, {:uninspected_evidence_ids, ["adjacent"]}} = Records.validate(forged, [unit], ["events"])
    assert Records.validate(object, [unit], ["events"]) == Records.validate(object, [unit], ["events"])
  end
end
