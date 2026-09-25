defmodule FountProbe.Action.Layout do
  @moduledoc "Maps exact action excerpts to lines in a verified rendered PDF. Ambiguous matches remain unavailable."

  def measure(model, action_units, report_id, reader) when is_function(reader, 1) do
    with {:ok, %{"payload" => payload} = row} <- reader.(report_id),
         :ok <- validate_report(model, report_id, row, payload),
         pdf = get_in(payload, ["data", "candidate_pdf"]),
         path when is_binary(path) <- pdf["path"],
         {:ok, bytes} <- File.read(path),
         true <- String.starts_with?(bytes, "%PDF-") or {:error, :invalid_layout_pdf},
         true <- Fount.ID.hash(bytes) == pdf["sha256"] or {:error, :pdf_hash_mismatch},
         {:ok, extracted} <- extract(path),
         {:ok, regions} <- regions(extracted, action_units) do
      {:ok,
       %{
         "printed_lines" => Enum.sum(Enum.map(regions, & &1["line_count"])),
         "line_regions" => regions,
         "layout_status" => "measured_from_pdf",
         "layout_report_id" => report_id,
         "settings_sha256" => pdf["settings_sha256"],
         "pdf_sha256" => pdf["sha256"]
       }}
    else
      false -> {:error, :invalid_layout_pdf}
      {:error, _} = error -> error
      _ -> {:error, :invalid_layout_report}
    end
  end

  def measure(_, _, _, _), do: {:error, :missing_report_reader}

  defp validate_report(model, id, row, payload) when is_map(payload) do
    pdf = get_in(payload, ["data", "candidate_pdf"])

    if row["id"] == id and payload["id"] == id and
         payload["tool"] == "layout_compare" and payload["status"] == "complete" and
         payload["screenplay_id"] == model.id and
         payload["primary_revision_id"] == model.revision.id and
         is_map(pdf) and pdf["source_revision"] == model.revision.id and
         is_binary(pdf["settings_sha256"]) and is_binary(pdf["sha256"]),
       do: :ok,
       else: {:error, :invalid_layout_report}
  end

  defp validate_report(_, _, _, _), do: {:error, :invalid_layout_report}

  defp extract(path) do
    case System.find_executable("pdftotext") do
      nil ->
        {:error, :pdftotext_unavailable}

      executable ->
        case System.cmd(executable, ["-layout", path, "-"], stderr_to_stdout: true) do
          {output, 0} -> {:ok, output}
          _ -> {:error, :pdf_text_extraction_failed}
        end
    end
  end

  defp regions(extracted, units) do
    lines =
      extracted
      |> String.split("\f")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {page, page_number} ->
        page
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.map(fn {line, line_number} ->
          %{page: page_number, line: line_number, words: words(line)}
        end)
      end)

    tokens =
      Enum.flat_map(lines, fn line ->
        Enum.map(line.words, &{&1, line.page, line.line})
      end)

    Enum.reduce_while(units, {:ok, []}, fn unit, {:ok, acc} ->
      sought = words(unit["text"])
      matches = subsequences(tokens, sought)

      case matches do
        [match] ->
          positions = match |> Enum.map(fn {_, page, line} -> {page, line} end) |> Enum.uniq()

          region = %{
            "evidence_id" => unit["evidence_id"],
            "target" => unit["target"],
            "page_start" => elem(hd(positions), 0),
            "page_end" => elem(List.last(positions), 0),
            "line_count" => length(positions),
            "lines" =>
              Enum.map(positions, fn {page, line} -> %{"page" => page, "line" => line} end)
          }

          {:cont, {:ok, acc ++ [region]}}

        [] ->
          {:halt, {:error, {:layout_excerpt_not_found, unit["evidence_id"]}}}

        _ ->
          {:halt, {:error, {:ambiguous_layout_excerpt, unit["evidence_id"]}}}
      end
    end)
  end

  defp words(value) when is_binary(value),
    do: Regex.scan(~r/[\p{L}\p{N}]+/u, String.downcase(value)) |> List.flatten()

  defp subsequences(_, []), do: []

  defp subsequences(tokens, sought) do
    size = length(sought)

    tokens
    |> Enum.chunk_every(size, 1, :discard)
    |> Enum.filter(fn group -> Enum.map(group, &elem(&1, 0)) == sought end)
  end
end
