defmodule Fount.Intelligence.ImportCueDecisions do
  @moduledoc "Payload ownership and source-correlated cue dispositions, independent of provider transport."

  @reasons ~w(supported_speaker printed_text message_header organization_or_prop ambiguous_identity ambiguous_role insufficient_evidence)

  def owned_elements(binding, chunk) do
    Enum.filter(binding["literal_elements"] || [], fn row ->
      start = row["content_byte_start"] || row["source_byte_start"]

      is_integer(start) and start >= chunk["source_byte_start"] and
        start < chunk["source_byte_end"]
    end)
  end

  def validate(object, chunk, binding, evidence_validator) do
    cues = owned_elements(binding, chunk) |> Enum.filter(&(&1["kind"] == "character"))
    processed = MapSet.new(object["coverage"]["processed_span_ids"])
    required = Enum.filter(cues, &processed_cue?(&1, chunk, processed))

    ids =
      Enum.map(object["cue_decisions"], fn row ->
        if is_map(row), do: row["literal_element_id"], else: nil
      end)

    if Enum.sort(ids) == Enum.sort(Enum.map(required, & &1["element_id"])) and
         Enum.all?(
           object["cue_decisions"],
           &valid_decision?(&1, required, object, chunk, evidence_validator)
         ),
       do: :ok,
       else: {:error, :invalid_cue_decisions}
  end

  defp processed_cue?(cue, chunk, processed) do
    start = cue["content_byte_start"] || cue["source_byte_start"]

    Enum.any?(chunk["spans"], fn span ->
      not span["context_only"] and MapSet.member?(processed, span["span_id"]) and
        start >= span["byte_start"] and start < span["byte_end"]
    end)
  end

  defp valid_decision?(decision, cues, object, chunk, validator) when is_map(decision) do
    cue = Enum.find(cues, &(&1["element_id"] == decision["literal_element_id"]))

    Enum.sort(Map.keys(decision)) ==
      Enum.sort(~w(literal_element_id disposition entity_id reason_code evidence)) and
      decision["reason_code"] in @reasons and validator.(decision["evidence"]) and
      correlated?(decision["evidence"], cue, chunk) and
      valid_disposition?(decision, cue, object, chunk)
  end

  defp valid_decision?(_, _, _, _, _), do: false

  defp valid_disposition?(%{"disposition" => "character"} = decision, cue, object, chunk) do
    entity = Enum.find(object["entities"], &(&1["local_id"] == decision["entity_id"]))
    finish = cue["content_byte_end"] || cue["source_byte_end"]

    entity != nil and entity["kind"] == "character" and
      decision["reason_code"] == "supported_speaker" and
      finish <= chunk["source_byte_end"] and
      Enum.any?(
        object["occurrences"],
        &(&1["entity_id"] == decision["entity_id"] and
            &1["literal_element_id"] == cue["element_id"] and &1["role"] == "speaker")
      )
  end

  defp valid_disposition?(
         %{"disposition" => disposition, "entity_id" => nil} = decision,
         cue,
         object,
         _chunk
       )
       when disposition in ["non_character", "unresolved"] do
    allowed =
      if disposition == "non_character",
        do: ~w(printed_text message_header organization_or_prop),
        else: ~w(ambiguous_identity ambiguous_role insufficient_evidence)

    decision["reason_code"] in allowed and
      not Enum.any?(
        object["occurrences"],
        &(&1["literal_element_id"] == cue["element_id"] and &1["role"] == "speaker")
      )
  end

  defp valid_disposition?(_, _, _, _), do: false

  def correlated?(evidence, literal, chunk) when is_map(literal) and is_list(evidence) do
    start = literal["content_byte_start"] || literal["source_byte_start"]
    finish = literal["content_byte_end"] || literal["source_byte_end"]
    spans = Map.new(chunk["spans"], &{&1["span_id"], &1})

    Enum.any?(evidence, &overlaps_literal?(&1, spans, start, finish))
  end

  def correlated?(_, _, _), do: false

  defp overlaps_literal?(row, spans, start, finish) when is_map(row) do
    case spans[row["span_id"]] do
      %{"context_only" => false, "byte_start" => offset} ->
        is_integer(row["byte_start"]) and is_integer(row["byte_end"]) and
          offset + row["byte_start"] < finish and offset + row["byte_end"] > start

      _ ->
        false
    end
  end

  defp overlaps_literal?(_, _, _, _), do: false

  def references_correlated?(occurrences, binding, chunk) do
    index = Map.new(owned_elements(binding, chunk), &{&1["element_id"], &1})

    Enum.all?(occurrences, fn row ->
      is_nil(row["literal_element_id"]) or
        correlated?(row["evidence"], index[row["literal_element_id"]], chunk)
    end)
  end

  def diagnostics(object, chunk, binding) do
    object = if is_map(object), do: object, else: %{}
    literals = owned_elements(binding, chunk)
    index = Map.new(literals, &{&1["element_id"], &1})
    decisions = map_rows(object["cue_decisions"])
    present = MapSet.new(decisions, & &1["literal_element_id"])

    missing =
      literals
      |> Enum.filter(
        &(&1["kind"] == "character" and not MapSet.member?(present, &1["element_id"]))
      )
      |> Enum.map(& &1["element_id"])

    wrong =
      map_rows(object["occurrences"])
      |> Enum.filter(
        &(is_binary(&1["literal_element_id"]) and
            not correlated?(&1["evidence"], index[&1["literal_element_id"]], chunk))
      )
      |> Enum.map(& &1["literal_element_id"])

    ids =
      (missing ++ wrong) |> Enum.filter(&(is_binary(&1) and byte_size(&1) <= 120)) |> Enum.uniq()

    %{
      "chunk_id" => chunk["chunk_id"],
      "related_ids" => Enum.take(ids, 20),
      "related_ids_truncated" => max(length(ids) - 20, 0),
      "ranges" =>
        ids
        |> Enum.take(20)
        |> Enum.flat_map(fn id ->
          if index[id],
            do: [
              %{
                "element_id" => id,
                "byte_start" => index[id]["content_byte_start"],
                "byte_end" => index[id]["content_byte_end"]
              }
            ],
            else: []
        end),
      "facts" => [
        %{"missing_cue_decisions" => length(missing)},
        %{"literal_evidence_mismatches" => length(wrong)}
      ]
    }
  end

  defp map_rows(rows) when is_list(rows), do: Enum.filter(rows, &is_map/1)
  defp map_rows(_), do: []

  def remap(results, remap) do
    Enum.flat_map(results, fn result ->
      Enum.map(result["cue_decisions"], &remap_decision(&1, result["chunk_id"], remap))
    end)
  end

  defp remap_decision(%{"entity_id" => nil} = row, _chunk, _remap), do: row

  defp remap_decision(row, chunk, remap) do
    ref = chunk <> ":" <> row["entity_id"]
    Map.put(row, "entity_id", Map.get(remap, ref, ref))
  end

  def unresolved(decisions) do
    decisions
    |> Enum.filter(&(&1["disposition"] == "unresolved"))
    |> Enum.map(fn row ->
      %{
        "span_ids" => Enum.map(row["evidence"], & &1["span_id"]) |> Enum.uniq(),
        "entity_ids" => [],
        "reason_code" => row["reason_code"],
        "explanation" => "Unresolved source cue " <> row["literal_element_id"]
      }
    end)
  end
end
