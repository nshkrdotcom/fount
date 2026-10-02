defmodule Fount.Intelligence.ImportV2ContractTest do
  use ExUnit.Case, async: true
  alias Fount.Intelligence.{ImportAssessment, ImportCueDecisions, ImportIdentity, ImportReview}

  test "every owned cue needs a decision and an existing wrong cue ID cannot borrow evidence" do
    {binding, plan, chunk, result} = fixture()
    assert :ok = ImportAssessment.validate_chunk(result, chunk, binding)
    missing = Map.put(result, "cue_decisions", [])

    assert {:error, :invalid_cue_decisions} =
             ImportAssessment.validate_chunk(missing, chunk, binding)

    other = List.last(binding["literal_elements"])["element_id"]
    original = hd(result["occurrences"])["literal_element_id"]

    forged =
      result
      |> put_in(["occurrences", Access.at(0), "literal_element_id"], other)
      |> put_in(["occurrences", Access.at(1), "literal_element_id"], original)

    assert {:error, :literal_evidence_mismatch} =
             ImportAssessment.validate_chunk(forged, chunk, binding)

    assert {:ok, aggregate} = ImportAssessment.assemble([result], nil, binding, plan: plan)
    assert aggregate["coverage"]["unassessed_cues"] == 0
    assert aggregate["span_bindings"] != %{}

    assert {:error, :duplicate_cue_ownership} =
             ImportAssessment.assemble([result, result], nil, binding, plan: plan)
  end

  test "explicit non-character decisions survive without an entity and uncertainty becomes an issue" do
    {binding, plan, chunk, result} = fixture()

    printed =
      Map.update!(result, "cue_decisions", fn rows ->
        Enum.map(
          rows,
          &%{
            &1
            | "disposition" => "non_character",
              "entity_id" => nil,
              "reason_code" => "printed_text"
          }
        )
      end)

    printed = %{printed | "entities" => [], "occurrences" => []}
    assert :ok = ImportAssessment.validate_chunk(printed, chunk, binding)
    assert {:ok, aggregate} = ImportAssessment.assemble([printed], nil, binding, plan: plan)
    assert length(aggregate["cue_decisions"]) == 2
    assert aggregate["entities"] == []
    uncertain = put_in(result, ["entities", Access.at(0), "certainty"], "uncertain")
    assert {:ok, partial} = ImportAssessment.assemble([uncertain], nil, binding, plan: plan)
    assert partial["unresolved"] != []
  end

  test "reconciliation cannot merge different kinds or use invented relation evidence" do
    {_binding, _plan, _chunk, result} = fixture()
    refs = Enum.map(result["entities"], &(result["chunk_id"] <> ":" <> &1["local_id"]))
    evidence = Enum.flat_map(result["entities"], & &1["evidence"])

    relation = %{
      "members" => refs,
      "kind" => "character",
      "label" => "Shared",
      "relation" => "same_entity",
      "reason_code" => "explicit_alias",
      "explanation" => "An explicit alias would require source proof.",
      "evidence" => evidence
    }

    object = %{"groups" => [relation], "unresolved" => []}
    mixed = put_in(result, ["entities", Access.at(1), "kind"], "document_text")

    assert {:error, :invalid_reconciliation} =
             ImportAssessment.validate_reconciliation(object, [mixed])

    invented =
      put_in(object, ["groups", Access.at(0), "evidence", Access.at(0), "quote"], "invented")

    assert {:error, :invalid_reconciliation} =
             ImportAssessment.validate_reconciliation(invented, [result])
  end

  test "identity support is independent of label, output order and duplicated evidence" do
    {binding, plan, _chunk, result} = fixture()
    spans = ImportAssessment.span_bindings(plan)
    assessment = %{"project_id" => Fount.ID.v4(), "revision_id" => Fount.ID.v4()}
    entity = hd(result["entities"])
    rows = result["occurrences"]
    handle = ImportIdentity.handle(assessment, entity, rows, spans)

    reordered =
      rows
      |> Enum.reverse()
      |> Enum.map(
        &Map.update!(&1, "evidence", fn evidence -> Enum.reverse(evidence ++ evidence) end)
      )

    assert ImportIdentity.handle(
             assessment,
             Map.put(entity, "label", "Renamed"),
             reordered,
             spans
           ) == handle

    assert ImportIdentity.handle(assessment, entity, [hd(rows)], spans) != handle
    assert binding["literal_elements"] != []
  end

  test "self-review without distinguishing evidence abstains rather than flipping a role confidently" do
    {_binding, _plan, _chunk, proposed} = fixture()

    reviewed =
      Map.update!(proposed, "cue_decisions", fn rows ->
        Enum.map(
          rows,
          &%{
            &1
            | "disposition" => "non_character",
              "entity_id" => nil,
              "reason_code" => "printed_text"
          }
        )
      end)

    {corrected, diff} = ImportReview.finalize(proposed, reviewed)
    assert Enum.all?(corrected["cue_decisions"], &(&1["disposition"] == "unresolved"))
    assert corrected["occurrences"] == []
    assert diff["changed_cues"] == 2
  end

  test "malformed list entries and diagnostic evidence fail without raising" do
    {binding, _plan, chunk, result} = fixture()

    for key <- ~w(entities occurrences cue_decisions), malformed <- [nil, 7, "wrong", []] do
      assert {:error, _} =
               ImportAssessment.validate_chunk(Map.put(result, key, [malformed]), chunk, binding)
    end

    for malformed <- [
          nil,
          7,
          "wrong",
          %{},
          %{"span_id" => "span-1", "byte_start" => "wrong", "byte_end" => nil}
        ] do
      bad = put_in(result, ["occurrences", Access.at(0), "evidence"], [malformed])
      assert {:error, _} = ImportAssessment.validate_chunk(bad, chunk, binding)
      assert is_map(ImportCueDecisions.diagnostics(bad, chunk, binding))
    end
  end

  test "reconciliation retains exact bounded Unicode source context and absolute coordinates" do
    {binding, plan, _chunk, result} = fixture()

    assert {:ok, prompt} =
             ImportAssessment.reconciliation_prompt([result], plan: plan, binding: binding)

    [_, json] = String.split(prompt, "\n", parts: 2)
    payload = Jason.decode!(json)
    assert Enum.all?(payload["entities"], &(&1["absolute_evidence"] != []))
    source = hd(plan["chunks"])["spans"] |> hd() |> Map.fetch!("text")

    for entity <- payload["entities"], context <- entity["source_context"] do
      assert String.valid?(context["text"])
      assert byte_size(context["text"]) <= 400

      assert context["text"] ==
               binary_part(
                 source,
                 context["context_byte_start"],
                 context["context_byte_end"] - context["context_byte_start"]
               )
    end
  end

  defp fixture do
    source = "MIRA\r\nHello.\r\n\r\nNÓRA\r\nStop.\r\n"

    screenplay =
      source |> Fount.parse!() |> Fount.Screenplay.from_document(cast_resolution: :manual)

    {:ok, binding} = ImportAssessment.source_descriptor(screenplay)
    {:ok, plan} = ImportAssessment.plan_source(source)
    [chunk] = plan["chunks"]
    [span] = chunk["spans"]
    cues = Enum.filter(binding["literal_elements"], &(&1["kind"] == "character"))

    evidence =
      Enum.map(cues, fn cue ->
        %{
          "span_id" => span["span_id"],
          "byte_start" => cue["content_byte_start"],
          "byte_end" => cue["content_byte_end"],
          "quote" => cue["literal"]
        }
      end)

    entities =
      Enum.zip(cues, evidence)
      |> Enum.with_index(fn {cue, ev}, n ->
        %{
          "local_id" => "person-#{n}",
          "kind" => "character",
          "label" => cue["literal"],
          "aliases" => [],
          "certainty" => "supported",
          "confidence" => nil,
          "evidence" => [ev]
        }
      end)

    occurrences =
      Enum.zip(cues, evidence)
      |> Enum.with_index(fn {cue, ev}, n ->
        %{
          "local_id" => "occ-#{n}",
          "entity_id" => "person-#{n}",
          "literal_element_id" => cue["element_id"],
          "role" => "speaker",
          "certainty" => "supported",
          "evidence" => [ev]
        }
      end)

    decisions =
      Enum.map(
        occurrences,
        &%{
          "literal_element_id" => &1["literal_element_id"],
          "disposition" => "character",
          "entity_id" => &1["entity_id"],
          "reason_code" => "supported_speaker",
          "evidence" => &1["evidence"]
        }
      )

    result = %{
      "schema_version" => ImportAssessment.schema_version(),
      "chunk_id" => chunk["chunk_id"],
      "entities" => entities,
      "occurrences" => occurrences,
      "headings" => [],
      "cue_decisions" => decisions,
      "coverage" => %{"processed_span_ids" => chunk["payload_span_ids"], "omitted" => []},
      "unresolved" => []
    }

    {binding, plan, chunk, result}
  end
end
