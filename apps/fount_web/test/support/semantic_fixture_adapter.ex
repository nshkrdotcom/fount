defmodule FountWeb.SemanticFixtureAdapter do
  @moduledoc "Deterministic SI02 test-only adapter. It exercises real Inference/Completion/Run plumbing without a provider call."
  @behaviour Inference.Adapter

  alias Inference.{Capability, Request, Response}

  @model "gpt-6.1-sol"

  def client do
    Inference.Client.new!(
      adapter: __MODULE__,
      provider: :semantic_fixture,
      model: @model,
      metadata: %{fixture: :semantic_import_v1}
    )
  end

  @impl true
  def provider_kind, do: :local_model_endpoint

  @impl true
  def capabilities(_client) do
    [Capability.new(:response_format_json_schema, :supported, %{fixture: true})]
  end

  @impl true
  def complete(_client, %Request{} = request) do
    object = fixture_object(Request.user_prompt(request))

    {:ok,
     Response.new(
       id: "semantic-fixture-" <> Integer.to_string(:erlang.unique_integer([:positive])),
       provider: :semantic_fixture,
       model: @model,
       text: Jason.encode!(object),
       object: object,
       finish_reason: :stop,
       usage: %{input_tokens: 0, output_tokens: 0},
       metadata: %{fixture: true, live_provider: false}
     )}
  end

  defp fixture_object("Fount semantic import extraction. Return only the requested structured object.\n" <> encoded) do
    envelope = Jason.decode!(encoded)
    payload = Enum.find(envelope["spans"], &(not &1["context_only"]))
    elements = envelope["literal_elements"] || []

    {entities, occurrences, headings} =
      elements
      |> Enum.with_index(1)
      |> Enum.reduce({[], [], []}, fn {element, index}, {entities, occurrences, headings} ->
        case evidence_for(element, payload) do
          nil ->
            {entities, occurrences, headings}

          evidence ->
            local = "literal-#{index}"
            kind = element["kind"]

            case kind do
              "character" ->
                entity = entity(local, "character", character_label(element["literal"]), evidence)
                occurrence = occurrence("occ-#{index}", local, "speaker", element["element_id"], evidence)
                {[entity | entities], [occurrence | occurrences], headings}

              "location" ->
                entity = entity(local, "location", location_label(element["literal"]), evidence)
                occurrence = occurrence("occ-#{index}", local, "location_heading", element["element_id"], evidence)

                heading = %{
                  "heading_span_id" => evidence["span_id"],
                  "place_entity_id" => local,
                  "parent_place_label" => location_label(element["literal"]),
                  "subplace_label" => nil,
                  "geography_label" => nil,
                  "time_of_day" => heading_time(element["literal"]),
                  "date_or_era" => heading_parenthetical(element["literal"]),
                  "relative_time" => nil,
                  "modifiers" => [],
                  "certainty" => "supported",
                  "evidence" => [evidence]
                }

                {[entity | entities], [occurrence | occurrences], [heading | headings]}

              _ ->
                {entities, occurrences, headings}
            end
        end
      end)

    {entities, occurrences} = add_document_fixture(entities, occurrences, payload)
    {entities, occurrences} = add_physical_presence_fixture(entities, occurrences, payload)

    %{
      "schema_version" => "semantic_import_v1",
      "chunk_id" => envelope["chunk_id"],
      "entities" => Enum.reverse(entities),
      "occurrences" => Enum.reverse(occurrences),
      "headings" => Enum.reverse(headings),
      "coverage" => %{
        "processed_span_ids" => [payload["span_id"]],
        "omitted" => []
      },
      "unresolved" => []
    }
  end

  defp fixture_object("Reconcile validated semantic entities. Return only the requested structured object.\n" <> encoded) do
    rows = Jason.decode!(encoded)["entities"] || []

    doctor_groups =
      rows
      |> Enum.group_by(fn row ->
        row["label"]
        |> to_string()
        |> String.upcase()
        |> String.replace(~r/^DR\.\s+/, "")
      end)
      |> Enum.flat_map(fn {label, members} ->
        labels = Enum.map(members, &String.upcase(&1["label"] || ""))

        if length(members) >= 2 and Enum.any?(labels, &String.starts_with?(&1, "DR. ")) do
          [
            %{
              "members" => Enum.map(members, & &1["ref"]),
              "relation" => "same_entity",
              "label" => label,
              "kind" => hd(members)["kind"]
            }
          ]
        else
          []
        end
      end)

    separate_generic =
      rows
      |> Enum.filter(
        &(&1["kind"] == "character" and
            String.upcase(&1["label"] || "") in ["GUARD", "COP", "NURSE"])
      )
      |> Enum.group_by(&String.upcase(&1["label"] || ""))
      |> Enum.flat_map(fn {label, members} ->
        if length(members) >= 2 do
          [
            %{
              "members" => Enum.map(members, & &1["ref"]),
              "relation" => "separate_entities",
              "label" => label,
              "kind" => "character"
            }
          ]
        else
          []
        end
      end)

    %{"groups" => doctor_groups ++ separate_generic, "unresolved" => []}
  end

  defp fixture_object(_), do: %{"groups" => [], "unresolved" => []}

  defp evidence_for(element, payload) do
    start = element["source_byte_start"] - payload["byte_start"]
    finish = element["source_byte_end"] - payload["byte_start"]

    if start >= 0 and finish > start and finish <= byte_size(payload["text"]) do
      quote = binary_part(payload["text"], start, finish - start)
      evidence(payload, start, finish, quote)
    end
  end

  defp evidence(payload, start, finish, quote),
    do: %{
      "span_id" => payload["span_id"],
      "byte_start" => start,
      "byte_end" => finish,
      "quote" => quote
    }

  defp entity(id, kind, label, evidence),
    do: %{
      "local_id" => id,
      "kind" => kind,
      "label" => label,
      "aliases" => [],
      "certainty" => "supported",
      "confidence" => nil,
      "evidence" => [evidence]
    }

  defp occurrence(id, entity_id, role, literal_element_id, evidence),
    do: %{
      "local_id" => id,
      "entity_id" => entity_id,
      "role" => role,
      "literal_element_id" => literal_element_id,
      "certainty" => "supported",
      "evidence" => [evidence]
    }

  defp add_document_fixture(entities, occurrences, payload) do
    case exact_phrase(payload, "WORK ORDER") do
      nil -> {entities, occurrences}
      evidence ->
        id = "fixture-document-work-order"
        {[entity(id, "document_text", "WORK ORDER", evidence) | entities],
         [occurrence("fixture-document-occ", id, "printed_text", nil, evidence) | occurrences]}
    end
  end

  defp add_physical_presence_fixture(entities, occurrences, payload) do
    case Regex.run(~r/\b([A-Z][A-Z0-9' -]{1,40})\s+(?:crosses|enters|steps|walks)\b/u, payload["text"], return: :index) do
      [{full_start, _full_len}, {name_start, name_len}] ->
        name = binary_part(payload["text"], name_start, name_len) |> String.trim()
        evidence = evidence(payload, name_start, name_start + name_len, name)

        case Enum.find(entities, &(&1["kind"] == "character" and String.upcase(&1["label"]) == name)) do
          nil ->
            id = "fixture-presence-" <> Integer.to_string(full_start)
            {[entity(id, "character", name, evidence) | entities],
             [occurrence("fixture-presence-occ-#{full_start}", id, "physical_presence", nil, evidence) | occurrences]}

          existing ->
            {entities,
             [occurrence("fixture-presence-occ-#{full_start}", existing["local_id"], "physical_presence", nil, evidence) | occurrences]}
        end

      _ ->
        {entities, occurrences}
    end
  end

  defp exact_phrase(payload, phrase) do
    case :binary.match(payload["text"], phrase) do
      {start, len} -> evidence(payload, start, start + len, phrase)
      :nomatch -> nil
    end
  end

  defp character_label(literal) do
    literal
    |> to_string()
    |> String.replace(~r/\s*\((?:O\.S\.|V\.O\.|CONT'D|CONT’D)\)\s*$/u, "")
    |> String.trim()
  end

  defp location_label(literal) do
    literal
    |> to_string()
    |> String.replace(~r/^\s*(?:INT\.|EXT\.|INT\.\/EXT\.|I\/E\.)\s*/iu, "")
    |> String.split(~r/\s+-\s+/u)
    |> List.first()
    |> to_string()
    |> String.trim()
  end

  defp heading_time(literal) do
    case Regex.run(~r/\s+-\s+(DAY|NIGHT|LATE NIGHT|LATE AFTERNOON|PREDAWN)\s*(?:\([^)]*\))?\s*$/iu, to_string(literal), capture: :all_but_first) do
      [value] -> String.upcase(value)
      _ -> nil
    end
  end

  defp heading_parenthetical(literal) do
    case Regex.run(~r/\(([^)]+)\)\s*$/u, to_string(literal), capture: :all_but_first) do
      [value] -> value
      _ -> nil
    end
  end
end
