defmodule Fount.Intelligence.ImportEvaluationTest do
  use ExUnit.Case, async: true
  alias Fount.Intelligence.ImportEvaluation

  @root Path.join(__DIR__, "fixtures/import_gold")

  test "gold evaluation catches schema-valid printed people, false merges and abstention" do
    {source, gold, result} = fixture()
    assert :ok = ImportEvaluation.verify_source(result, source)
    assert {:ok, report} = ImportEvaluation.evaluate(result, gold)
    assert report["entity_precision"] == 1.0
    assert report["entity_recall"] == 1.0
    assert report["missing_occurrences"] == 0
    assert report["false_merges"] == 0

    printed =
      result
      |> Map.update!("entities", fn rows ->
        Enum.map(rows, fn row ->
          if row["local_id"] == "printed-form", do: Map.put(row, "kind", "character"), else: row
        end)
      end)
      |> Map.update!("occurrences", fn rows ->
        Enum.map(rows, fn row ->
          if row["entity_id"] == "printed-form", do: Map.put(row, "role", "speaker"), else: row
        end)
      end)

    assert {:ok, bad} = ImportEvaluation.evaluate(printed, gold)
    assert bad["false_people"] == 1
    assert bad["extra_occurrences"] == 1
    assert bad["missing_occurrences"] == 1

    merged =
      Map.update!(result, "occurrences", fn rows ->
        Enum.map(rows, fn row ->
          if row["entity_id"] == "guard-east",
            do: Map.put(row, "entity_id", "guard-west"),
            else: row
        end)
      end)

    assert {:ok, bad_merge} = ImportEvaluation.evaluate(merged, gold)
    assert bad_merge["false_merges"] == 1

    abstained = %{result | "entities" => [], "occurrences" => []}
    assert {:ok, empty} = ImportEvaluation.evaluate(abstained, gold)
    assert empty["entity_recall"] == 0.0
    assert empty["missing_occurrences"] == length(gold["occurrences"])

    assert {:error, :gold_source_mismatch} =
             ImportEvaluation.evaluate(result, Map.put(gold, "visible_source_sha256", "forged"))
  end

  test "a fabricated quote cannot be evaluated under an original source identity" do
    {source, _gold, result} = fixture()

    forged =
      put_in(
        result,
        ["occurrences", Access.at(0), "evidence", Access.at(0), "quote"],
        "fabricated"
      )

    assert {:error, :evaluation_source_mismatch} = ImportEvaluation.verify_source(forged, source)
  end

  test "duplicate claims cannot inflate recall and roles are scored separately" do
    {_source, gold, result} = fixture()
    duplicate = Map.update!(result, "occurrences", &(&1 ++ [hd(&1)]))
    assert {:ok, report} = ImportEvaluation.evaluate(duplicate, gold)
    assert report["extra_occurrences"] == 1
    assert report["occurrence_precision"] < 1.0
    assert report["roles"]["speaker"]["extra"] == 1
    assert report["roles"]["physical_presence"]["recall"] == 1.0
  end

  defp fixture do
    source = File.read!(Path.join(@root, "cast_ambiguity.fountain"))
    gold = @root |> Path.join("cast_ambiguity.gold.json") |> File.read!() |> Jason.decode!()

    occurrences =
      Enum.with_index(gold["occurrences"], fn row, index ->
        %{
          "local_id" => "occ-#{index}",
          "entity_id" => row["entity_id"],
          "role" => row["role"],
          "literal_element_id" => nil,
          "evidence" => [
            %{
              "span_id" => "payload",
              "byte_start" => row["byte_start"],
              "byte_end" => row["byte_end"],
              "quote" =>
                binary_part(source, row["byte_start"], row["byte_end"] - row["byte_start"])
            }
          ]
        }
      end)

    result = %{
      "binding" => %{"render_sha256" => gold["visible_source_sha256"]},
      "span_bindings" => %{"payload" => %{"byte_start" => 0, "byte_end" => byte_size(source)}},
      "entities" => Enum.map(gold["entities"], &%{"local_id" => &1["id"], "kind" => &1["kind"]}),
      "occurrences" => occurrences,
      "unresolved" => [],
      "coverage" => %{"complete" => true}
    }

    {source, gold, result}
  end
end
