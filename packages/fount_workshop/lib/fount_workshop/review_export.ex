defmodule FountWorkshop.ReviewExport do
  @moduledoc false
  alias FountWorkshop.{Session, Store, TableRead}
  def export(session_id, directory, services, opts \\ []) do
    with {:ok, session} <- Session.get(session_id, services), :ok <- File.mkdir_p(directory),
         {:ok, base} <- Store.call(services[:store], :load_revision, [session["screenplay_id"], session["base_revision_id"]]) do
      write!(directory, "request.json", session["request"])
      write!(directory, "strategies.json", session["strategies"])
      write!(directory, "session.json", Map.delete(session, "candidates"))
      File.write!(Path.join(directory, "base.fountain"), Fount.Screenplay.to_fountain(base, mode: :spec))
      results = Enum.map(session["candidates"], fn candidate -> export_candidate(base, candidate, directory, services, opts) end)
      rows = Enum.map_join(results, "\n\n", fn row ->
        "## " <> row["label"] <> "\n\nRead [candidate pages](" <> row["pages"] <> ") before the checks.\n\n" <>
          "Candidate `#{row["id"]}`; performed-word delta #{row["word_delta"]}; measured page delta #{inspect(row["page_delta"])}.\n\n" <>
          "[Review, lineage and exact checks](#{row["review"]})\n\n" <> row["status_note"]
      end)
      text = "# Writer review\n\n" <> session["request"]["instruction"] <> "\n\n" <>
        "[Base pages](base.fountain) | [Approaches](strategies.json) | [Request](request.json)\n\n" <>
        "No draft has been accepted by exporting this packet. Compare actual writing; tool probabilities are not quality scores. A null page delta means no comparable measured PDFs.\n\n" <>
        rows <> "\n\n## Remaining work\n\n```json\n" <> Jason.encode!(session["progress"], pretty: true) <> "\n```\n"
      File.write!(Path.join(directory, "review.md"), text)
      manifest = %{"session_id" => session_id, "base_revision_id" => base.revision.id, "candidates" => results,
        "files" => Path.wildcard(Path.join(directory, "*")) |> Enum.filter(&File.regular?/1) |> Enum.map(fn path -> %{"path" => Path.basename(path), "sha256" => hash(File.read!(path))} end)}
      write!(directory, "review.manifest.json", manifest)
      if Enum.any?(results, &(&1["pdf"]["status"] == "failed")) do
        {:error, {:requested_pdf_failed, manifest}}
      else
        {:ok, manifest}
      end
    end
  end
  defp export_candidate(base, candidate, directory, services, opts) do
    model = candidate["screenplay"]; id = candidate["id"]
    pages = id <> ".fountain"; review = id <> ".review.json"
    File.write!(Path.join(directory, pages), Fount.Screenplay.to_fountain(model, mode: :spec))
    report_ids = candidate["provenance"]["report_ids"] || []
    reports = Enum.map(report_ids, fn report_id -> case Store.call(services[:store], :report, [report_id]) do {:ok, report} -> report["payload"]; {:error, _} -> %{"id" => report_id, "status" => "unavailable"} end end)
    layout = Enum.find(reports, &(&1["tool"] == "layout_compare"))
    pdf = if Keyword.get(opts, :pdf, false), do: FountWorkshop.Writing.Layout.render(services[:renderer], model, Path.join(directory, id <> ".pdf"), opts), else: {:error, :not_requested}
    {:ok, table} = TableRead.export(model, Path.join(directory, id <> ".read.json"), :json)
    {:ok, html} = TableRead.export(model, Path.join(directory, id <> ".read.html"), :html)
    packet = %{"candidate_id" => id, "base_revision_id" => base.revision.id, "result_revision_id" => model.revision.id,
      "content_hash" => model.revision.content_hash, "strategy" => candidate["strategy"], "change_groups" => candidate["change_groups"],
      "lineage" => candidate["lineage"], "provenance" => candidate["provenance"], "reports" => reports,
      "structural_diff" => Fount.Screenplay.Model.plain(Fount.Screenplay.diff(base, model)),
      "source_diff" => Enum.map(String.myers_difference(Fount.Screenplay.to_fountain(base), Fount.Screenplay.to_fountain(model)), fn {kind, text} -> %{"kind" => to_string(kind), "text" => text} end),
      "pdf" => result(pdf), "table_read" => Fount.Screenplay.Model.plain(table), "html" => Fount.Screenplay.Model.plain(html)}
    write!(directory, review, packet)
    # This is a review form, never a pre-filled acceptance claim.
    write!(directory, id <> ".decision.json", %{"candidate_id" => id, "content_hash" => model.revision.content_hash, "actor" => "", "report_ids" => report_ids, "overrides" => []})
    %{"id" => id, "label" => candidate["label"], "pages" => pages, "review" => review, "word_delta" => words(model) - words(base),
      "pdf" => result(pdf),
      "page_delta" => if(layout && layout["data"]["same_settings"], do: layout["data"]["candidate_pages"] - layout["data"]["base_pages"], else: nil),
      "status_note" => "Decision: #{candidate["status"] || "open"}. Failed and uncertain checks remain visible; explicit writer approval is required."}
  end
  def words(model) do
    model |> Fount.Screenplay.Editor.spec_ir() |> Map.fetch!(:elements) |> Enum.filter(&(&1.type in [:action, :dialogue, :parenthetical, :lyric]))
      |> Enum.map(&(length(Regex.scan(~r/[\p{L}\p{N}]+(?:['\x{2019}-][\p{L}\p{N}]+)*/u, Fount.Fountain.Inline.plain(&1.text))))) |> Enum.sum()
  end
  defp result({:ok, value}), do: %{"status" => "complete", "result" => Fount.Screenplay.Model.plain(value)}
  defp result({:error, :not_requested}), do: %{"status" => "not_requested"}
  defp result({:error, reason}), do: %{"status" => "failed", "reason" => inspect(reason, limit: 10, printable_limit: 500)}
  defp write!(dir, name, value), do: File.write!(Path.join(dir, name), Jason.encode!(Fount.Screenplay.Model.plain(value), pretty: true))
  defp hash(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
