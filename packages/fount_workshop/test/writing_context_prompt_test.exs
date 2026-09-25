defmodule FountWorkshop.WritingContextPromptTest do
  use ExUnit.Case, async: true

  test "large saved inspections fit a writing prompt without losing report identity" do
    edge = %{
      "from" => "setup-id",
      "to" => "use-id",
      "evidence_ids" => ["exact-evidence-id"],
      "assessment" => String.duplicate("reasoning ", 100)
    }

    report = %{
      "id" => "saved-report-id",
      "tool" => "dependencies",
      "status" => "partial",
      "coverage" => %{"tested_pairs" => 300},
      "data" => %{"edges" => List.duplicate(edge, 300)},
      "provenance" => %{"responses" => List.duplicate(String.duplicate("x", 1000), 300)},
      "errors" => [%{"code" => "incomplete"}],
      "findings" => []
    }

    full = %{"selected_pages" => [%{"text" => "Mara takes the key."}], "inspections" => [report]}
    compact = FountWorkshop.Writing.Context.prompt_data(full)

    assert byte_size(Jason.encode!(full)) > 100_000
    assert byte_size(Jason.encode!(compact)) < 50_000
    assert get_in(compact, ["inspections", Access.at(0), "id"]) == "saved-report-id"
    assert get_in(compact, ["inspections", Access.at(0), "status"]) == "partial"
    assert get_in(compact, ["inspections", Access.at(0), "data", "edges", "total"]) == 300

    assert get_in(compact, [
             "inspections",
             Access.at(0),
             "data",
             "edges",
             "sample",
             Access.at(0),
             "evidence_ids"
           ]) ==
             ["exact-evidence-id"]

    assert report["data"]["edges"] |> length() == 300
  end
end
