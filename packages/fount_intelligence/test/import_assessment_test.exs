defmodule Fount.Intelligence.ImportAssessmentTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.ImportAssessment

  test "chunk planning preserves every UTF-8 source byte and marks overlap context-only" do
    source = String.duplicate("INT. CAFÉ – NIGHT\nMÁRIA enters.\n", 20)

    assert {:ok, plan} =
             ImportAssessment.plan_source(source,
               limits: %{"payload_bytes" => 96, "context_bytes" => 32, "max_chunks" => 64}
             )

    payload =
      plan["chunks"]
      |> Enum.flat_map(& &1["spans"])
      |> Enum.reject(& &1["context_only"])
      |> Enum.map_join(& &1["text"])

    assert payload == source
    assert plan["source_bytes"] == byte_size(source)
    assert plan["chunk_count"] > 1

    plan["chunks"]
    |> Enum.drop(1)
    |> Enum.each(fn chunk ->
      assert Enum.any?(chunk["spans"], & &1["context_only"])

      assert Enum.all?(
               Enum.filter(chunk["spans"], & &1["context_only"]),
               &is_nil(&1["byte_start"])
             )
    end)
  end

  test "scene-aware planning keeps ordinary scenes whole and splits only an oversized scene" do
    source =
      "TITLE\n\nINT. ONE - DAY\n" <>
        String.duplicate("small action\n", 3) <>
        "INT. TWO - NIGHT\n" <> String.duplicate("large action café\n", 30)

    first = :binary.match(source, "INT. ONE - DAY") |> elem(0)
    second = :binary.match(source, "INT. TWO - NIGHT") |> elem(0)

    assert {:ok, plan} =
             ImportAssessment.plan_source(source,
               scene_starts: [first, second],
               limits: %{"payload_bytes" => 120, "context_bytes" => 32}
             )

    assert plan["chunking"]["mode"] == "scene_aware"
    assert plan["chunking"]["oversize_scene_splits"] == 1

    payload =
      plan["chunks"]
      |> Enum.flat_map(& &1["spans"])
      |> Enum.reject(& &1["context_only"])
      |> Enum.map_join(& &1["text"])

    assert payload == source
    assert Enum.any?(plan["chunks"], &(&1["source_byte_start"] == second))
  end

  test "server caps reject client limit increases" do
    assert {:error, :limit_exceeds_server_cap} =
             ImportAssessment.plan_source("INT. ROOM - DAY\n",
               limits: %{"payload_bytes" => 48_001}
             )
  end

  test "closed limit validation rejects tiny UTF-8 payloads, unknown keys, and excessive call ceilings" do
    assert {:error, :invalid_limits} = ImportAssessment.validate_limits(%{"payload_bytes" => 3})
    assert {:error, :unsupported_limit} = ImportAssessment.validate_limits(%{"unbounded" => 1})

    assert {:error, :limit_exceeds_server_cap} =
             ImportAssessment.validate_limits(%{"max_inference_calls" => 131})

    assert {:ok, limits} = ImportAssessment.validate_limits(%{"max_inference_calls" => 10})
    assert limits["payload_bytes"] == 48_000
  end

  test "validator accepts exact payload evidence and rejects context-only evidence" do
    source = "GUARD\nStop.\n"

    assert {:ok, plan} =
             ImportAssessment.plan_source(source,
               limits: %{"payload_bytes" => 8, "context_bytes" => 8}
             )

    [first, second | _] = plan["chunks"]

    assert :ok = ImportAssessment.validate_chunk(valid_result(first, "GUARD"), first)

    context = Enum.find(second["spans"], & &1["context_only"])
    assert context

    bad = %{
      valid_result(second, payload_text(second))
      | "entities" => [
          entity("person", "GUARD", evidence(context, 0, byte_size(context["text"])))
        ]
    }

    assert {:error, :invalid_entity} = ImportAssessment.validate_chunk(bad, second)
  end

  test "validator rejects boneyard and inline-note evidence plus forged literal element ids" do
    source = "/* HIDDEN PERSON */\n[[SECRET PERSON]]\nVISIBLE\n"
    assert {:ok, plan} = ImportAssessment.plan_source(source)
    [chunk] = plan["chunks"]
    payload = Enum.find(chunk["spans"], &(not &1["context_only"]))

    hidden_start = :binary.match(payload["text"], "HIDDEN PERSON") |> elem(0)
    hidden = entity("hidden", "HIDDEN PERSON", evidence(payload, hidden_start, hidden_start + 13))

    bad_hidden = %{
      valid_result(chunk, "VISIBLE")
      | "entities" => [hidden],
        "occurrences" => [
          occurrence("hidden-occ", "hidden", "mentioned", nil, hd(hidden["evidence"]))
        ]
    }

    assert {:error, :invalid_entity} = ImportAssessment.validate_chunk(bad_hidden, chunk)

    note_start = :binary.match(payload["text"], "SECRET PERSON") |> elem(0)
    note = entity("note", "SECRET PERSON", evidence(payload, note_start, note_start + 13))

    bad_note = %{
      valid_result(chunk, "VISIBLE")
      | "entities" => [note],
        "occurrences" => [occurrence("note-occ", "note", "mentioned", nil, hd(note["evidence"]))]
    }

    assert {:error, :invalid_entity} = ImportAssessment.validate_chunk(bad_note, chunk)

    good = valid_result(chunk, "VISIBLE")
    forged = put_in(good, ["occurrences", Access.at(0), "literal_element_id"], "not-in-envelope")
    binding = %{"literal_elements" => []}
    assert {:error, :invalid_occurrence} = ImportAssessment.validate_chunk(forged, chunk, binding)
  end

  test "title-page metadata is typed source context but cannot manufacture cast evidence" do
    source = "Title: PRIVATE DRAFT\nAuthor: PRINTED PERSON\n\nINT. ROOM - DAY\nMIRA enters.\n"

    screenplay =
      source |> Fount.parse!() |> Fount.Screenplay.from_document(cast_resolution: :manual)

    assert {:ok, descriptor} = ImportAssessment.source_descriptor(screenplay)
    assert descriptor["metadata_ranges"] != []

    assert {:ok, plan} =
             ImportAssessment.plan_source(descriptor["visible_source"],
               metadata_ranges: descriptor["metadata_ranges"]
             )

    [chunk] = plan["chunks"]
    payload = Enum.find(chunk["spans"], &(not &1["context_only"]))
    assert payload["metadata_ranges"] != []

    start = :binary.match(payload["text"], "PRINTED PERSON") |> elem(0)
    ev = evidence(payload, start, start + byte_size("PRINTED PERSON"))

    bad = %{
      valid_result(chunk, "MIRA")
      | "entities" => [entity("author", "PRINTED PERSON", ev)],
        "occurrences" => [occurrence("author-occ", "author", "mentioned", nil, ev)]
    }

    assert {:error, :invalid_entity} = ImportAssessment.validate_chunk(bad, chunk)
  end

  test "FDX keeps original artifact provenance while evidence binds converted revision spans" do
    xml =
      "<FinalDraft><Content>" <>
        "<Paragraph Type=\"Scene Heading\"><Text>INT. ROOM - NIGHT</Text></Paragraph>" <>
        "<Paragraph Type=\"Character\"><Text>MIRA</Text></Paragraph>" <>
        "<Paragraph Type=\"Dialogue\"><Text>Hello.</Text></Paragraph>" <>
        "</Content></FinalDraft>"

    assert {:ok, screenplay, _losses} = Fount.Screenplay.from_fdx(xml)
    assert {:ok, descriptor} = ImportAssessment.source_descriptor(screenplay)
    expected_sha = :crypto.hash(:sha256, xml) |> Base.encode16(case: :lower)

    assert descriptor["source_basis"] == "converted_revision"
    assert descriptor["source_sha256"] == expected_sha
    assert descriptor["visible_source"] == Fount.Screenplay.to_fountain(screenplay)
    assert descriptor["source_artifact_id"] == screenplay.import.id
    assert Enum.any?(descriptor["literal_elements"], &(&1["kind"] == "character"))
    assert Enum.any?(descriptor["literal_elements"], &(&1["kind"] == "location"))
    assert descriptor["scene_starts"] != []
  end

  test "assembly merges only explicit same-entity groups and keeps possible aliases separate" do
    chunk_a = chunk("chunk-1", "ALEX")
    chunk_b = chunk("chunk-2", "ALEX")
    a = valid_result(chunk_a, "ALEX", "a")
    b = valid_result(chunk_b, "ALEX", "b")
    binding = %{"source_sha256" => String.duplicate("a", 64), "model" => "gpt-6.1-sol"}

    possible = %{
      "groups" => [
        %{
          "members" => ["chunk-1:a", "chunk-2:b"],
          "relation" => "possible_same_entity",
          "label" => "ALEX",
          "kind" => "character"
        }
      ],
      "unresolved" => []
    }

    assert :ok = ImportAssessment.validate_reconciliation(possible, [a, b])
    assert {:ok, aggregate} = ImportAssessment.assemble([a, b], possible, binding)
    assert length(aggregate["entities"]) == 2

    same = put_in(possible, ["groups", Access.at(0), "relation"], "same_entity")
    assert {:ok, merged} = ImportAssessment.assemble([a, b], same, binding)
    assert length(merged["entities"]) == 1
    assert length(merged["occurrences"]) == 2
  end

  test "printed text can be represented as document_text without manufacturing a character" do
    chunk = chunk("chunk-1", "WORK ORDER")
    result = valid_result(chunk, "WORK ORDER", "document", "document_text", "printed_text")

    assert :ok = ImportAssessment.validate_chunk(result, chunk)
    assert hd(result["entities"])["kind"] == "document_text"
    assert hd(result["occurrences"])["role"] == "printed_text"
  end

  test "processed chunks with explicitly omitted payload remain partial" do
    input = chunk("chunk-1", "MIRA")
    result = valid_result(input, "MIRA")

    result =
      Map.put(result, "coverage", %{
        "processed_span_ids" => [],
        "omitted" => [
          %{"span_id" => hd(input["payload_span_ids"]), "reason" => "unsupported_scope"}
        ]
      })

    assert :ok = ImportAssessment.validate_chunk(result, input)

    assert {:ok, aggregate} =
             ImportAssessment.assemble([result], nil, %{}, expected_chunk_count: 1)

    assert aggregate["coverage"]["complete"] == false
  end

  test "oversized decoded objects and forged cross references fail the trusted validator" do
    input = chunk("chunk-1", "MIRA")
    result = valid_result(input, "MIRA")
    oversized = Map.put(result, "unresolved", [String.duplicate("x", 524_289)])
    assert {:error, :decoded_chunk_too_large} = ImportAssessment.validate_chunk(oversized, input)
    forged = put_in(result, ["occurrences", Access.at(0), "entity_id"], "other-chunk:person")
    assert {:error, :invalid_occurrence} = ImportAssessment.validate_chunk(forged, input)
  end

  defp valid_result(chunk, quote, id \\ "person", kind \\ "character", role \\ "speaker") do
    payload = Enum.find(chunk["spans"], &(not &1["context_only"]))
    {start, len} = :binary.match(payload["text"], quote)
    ev = evidence(payload, start, start + len)

    %{
      "schema_version" => ImportAssessment.schema_version(),
      "chunk_id" => chunk["chunk_id"],
      "entities" => [entity(id, quote, ev, kind)],
      "occurrences" => [
        %{
          "local_id" => "occ-#{id}",
          "entity_id" => id,
          "role" => role,
          "literal_element_id" => nil,
          "certainty" => "supported",
          "evidence" => [ev]
        }
      ],
      "headings" => [],
      "coverage" => %{"processed_span_ids" => chunk["payload_span_ids"], "omitted" => []},
      "unresolved" => []
    }
  end

  defp entity(id, label, evidence, kind \\ "character") do
    %{
      "local_id" => id,
      "kind" => kind,
      "label" => label,
      "aliases" => [],
      "certainty" => "supported",
      "confidence" => nil,
      "evidence" => [evidence]
    }
  end

  defp occurrence(id, entity_id, role, literal_element_id, evidence) do
    %{
      "local_id" => id,
      "entity_id" => entity_id,
      "role" => role,
      "literal_element_id" => literal_element_id,
      "certainty" => "supported",
      "evidence" => [evidence]
    }
  end

  defp chunk(id, text) do
    %{
      "chunk_id" => id,
      "ordinal" => 1,
      "spans" => [
        %{
          "span_id" => "#{id}-payload",
          "text" => text,
          "context_only" => false,
          "byte_start" => 0,
          "byte_end" => byte_size(text),
          "excluded_ranges" => [],
          "note_ranges" => [],
          "metadata_ranges" => []
        }
      ],
      "payload_span_ids" => ["#{id}-payload"],
      "payload_bytes" => byte_size(text),
      "source_byte_start" => 0,
      "source_byte_end" => byte_size(text)
    }
  end

  defp payload_text(chunk), do: Enum.find(chunk["spans"], &(not &1["context_only"]))["text"]

  defp evidence(span, start, finish) do
    %{
      "span_id" => span["span_id"],
      "byte_start" => start,
      "byte_end" => finish,
      "quote" => binary_part(span["text"], start, finish - start)
    }
  end
end
