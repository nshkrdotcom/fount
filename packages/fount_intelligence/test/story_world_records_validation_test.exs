defmodule RecordsValidationTest do
  alias Fount.Intelligence.StoryWorld.Records
  use ExUnit.Case, async: true

  test "new structured extraction cannot invent evidence" do
    assert {:error, _} =
             Records.validate(
               %{
                 "records" => [
                   %{
                     "id" => "x",
                     "kind" => "events",
                     "claim" => "A ghost.",
                     "subjects" => [],
                     "evidence_ids" => ["invented"],
                     "uncertainty" => "unknown"
                   }
                 ],
                 "summary" => "Ghost"
               },
               [],
               ["events"]
             )
  end

  test "extraction reports the exact local validation failure" do
    record = %{
      "id" => "a",
      "kind" => "events",
      "claim" => "A key changes hands.",
      "subjects" => [],
      "evidence_ids" => ["source-1"],
      "uncertainty" => "none"
    }

    units = [%{"evidence_id" => "source-1"}]
    object = %{"summary" => "A transfer.", "records" => [record]}
    assert :ok = Records.validate(object, units, ["events"])

    assert {:error, {:uninspected_evidence_ids, ["neighbor-1"]}} =
             Records.validate(
               put_in(object, ["records", Access.at(0), "evidence_ids"], ["neighbor-1"]),
               units,
               ["events"]
             )

    assert {:error, {:duplicate_extraction_ids, ["a"]}} =
             Records.validate(
               %{object | "records" => [record, record]},
               units,
               ["events"]
             )

    assert {:error, {:unrequested_extraction_kinds, ["props"]}} =
             Records.validate(
               put_in(object, ["records", Access.at(0), "kind"], "props"),
               units,
               ["events"]
             )
  end
end
