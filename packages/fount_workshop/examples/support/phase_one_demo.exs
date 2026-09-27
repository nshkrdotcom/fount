defmodule FountWorkshop.Examples.PhaseOneDemo do
  @moduledoc false
  alias Fount.{ID, Persistence, Query, Screenplay}
  alias Fount.Intelligence.Acquisition.Configuration
  alias Fount.Intelligence.Reporting.Report
  alias FountWorkshop.{Develop, Review, TableRead, TargetedRewrite}

  # Deliberately uses authored fixtures, not live model calls or a claim that a
  # human preferred either alternative. All persistence/export operations are real.
  def run(repo, opts) do
    directory = Keyword.fetch!(opts, :out)
    decision = Keyword.get(opts, :decision, :reject)
    unless decision in [:accept, :reject], do: raise(ArgumentError, "decision must be :accept or :reject")
    File.mkdir_p!(directory)
    key = "phase-one-demo-#{ID.v4()}"
    root = Screenplay.new(title: [{"Title", "The Unopened Door"}])
    {:ok, _} = Persistence.create(repo, key, root)
    first = client(draft("Mara slips a key under the locked door.", "I know you took it."))
    second = client(draft("Mara pockets the key and knocks.", "Tell me what you heard."))
    {:ok, developed} = Develop.run(repo, key, "Two strangers disagree about an unopened room.", first, clients: [first, second])
    [chosen, alternate] = developed.candidates
    {:ok, unchanged} = Persistence.load(repo, key)
    ensure!(unchanged.revision.id == root.revision.id, "develop changed the accepted head")
    {:ok, before_packet} = Review.packet(repo, chosen.id)
    ensure!(before_packet["source_diff"] != [], "development produced no page changes")
    {:ok, rejected} = Review.reject(repo, alternate.id, "fixture-writer")
    ensure!(rejected["decision"] == "rejected", "alternate was not rejected")
    {:ok, base} = Review.accept(repo, chosen.id, root.revision.id, review(chosen.id, before_packet))
    target = Enum.find(base.ir.elements, &(&1.text == "I know you took it."))
    rewrite = client(%{"changes" => [%{"element_id" => target.id, "text" => "Then why is the safe open?"}]})
    {:ok, revised} = TargetedRewrite.run(repo, key, [target.id], "Make the accusation indirect; keep the locked-door action.", rewrite)
    {:ok, saved} = Persistence.candidate(repo, revised.candidate.id)
    candidate = saved["screenplay"]
    ensure!(Query.node(candidate, target.id).text == "Then why is the safe open?", "rewrite was not materialized")
    {:ok, head} = Persistence.load(repo, key)
    ensure!(head.revision.id == base.revision.id, "candidate generation changed canon")
    {:ok, packet} = Review.packet(repo, revised.candidate.id)
    ensure!(packet["source_diff"] != [], "rewrite diff is empty")

    observe = Configuration.sandbox(%{"direct:indirect" => %{"different" => 0.85}})
    clients = %{observe: observe}
    {:ok, contrast} = Fount.Intelligence.run(base, "strategy_contrast", %{
      "brief" => "Challenge Mara without changing the established locked door.",
      "strategies" => [%{"id" => "direct", "approach" => "Accuse directly."},
        %{"id" => "indirect", "approach" => "Make her explain the physical evidence."}]
    }, clients)
    ensure!(contrast.status == "complete", "sandbox contrast was not measured")
    {:ok, comparison} = Fount.Intelligence.compare(base, candidate, [], clients)
    ensure!(comparison.status == "complete", "comparison was not complete")
    File.write!(Path.join(directory, "comparison.json"), Jason.encode!(Report.to_map(comparison), pretty: true))
    File.write!(Path.join(directory, "strategy_contrast.json"), Jason.encode!(Report.to_map(contrast), pretty: true))
    File.write!(Path.join(directory, "original.fountain"), Screenplay.to_fountain(base))
    File.write!(Path.join(directory, "candidate.fountain"), Screenplay.to_fountain(candidate))
    File.write!(Path.join(directory, "review.json"), Jason.encode!(Fount.Screenplay.Model.plain(packet), pretty: true))
    {:ok, read} = TableRead.export(candidate, Path.join(directory, "table_read.html"), :html)
    ensure!(read.turn_count == 1, "table-read dialogue was lost")
    pdf = if Keyword.get(opts, :pdf, false) do
      {:ok, result} = FountWorkshop.Export.PDF.export(candidate, Path.join(directory, "candidate.pdf"))
      ensure!(result.pages >= 1, "rendered PDF has no pages")
      %{"status" => "executed", "pages" => result.pages}
    else
      %{"status" => "not_requested"}
    end

    case decision do
      :accept ->
        {:ok, _} = Review.accept(repo, revised.candidate.id, base.revision.id, review(revised.candidate.id, packet))
      :reject ->
        {:ok, _} = Review.reject(repo, revised.candidate.id, "fixture-writer")
    end
    {:ok, final} = Persistence.load(repo, key)
    expected = if decision == :accept, do: candidate.revision.id, else: base.revision.id
    ensure!(final.revision.id == expected, "writer decision did not preserve the expected head")
    File.write!(Path.join(directory, "accepted.fountain"), Screenplay.to_fountain(final))
    manifest = %{"project_key" => key, "screenplay_id" => root.id, "decision" => to_string(decision),
      "base_revision_id" => base.revision.id, "candidate_revision_id" => candidate.revision.id,
      "accepted_revision_id" => final.revision.id, "candidate_id" => revised.candidate.id,
      "pdf" => pdf, "table_read_turns" => read.turn_count,
      "completion" => "Inference.Adapters.Mock", "measurement" => "Observe.Sandbox",
      "claim" => "engineering fixture demonstration; no human evaluation or live provider result"}
    File.write!(Path.join(directory, "manifest.json"), Jason.encode!(manifest, pretty: true))
    {:ok, manifest}
  end

  defp client(output), do: Inference.Client.new!(adapter: Inference.Adapters.Mock, provider: :mock,
    adapter_opts: [response_text: Jason.encode!(output)])
  defp draft(action, dialogue), do: %{"approach" => action, "scenes" => [%{"heading" => "INT. HALL - NIGHT",
    "elements" => [%{"type" => "action", "text" => action}, %{"type" => "character", "text" => "DAN"},
      %{"type" => "dialogue", "text" => dialogue}]}]}
  defp review(id, packet), do: %{"candidate_id" => id, "content_hash" => packet["content_hash"],
    "actor" => "fixture-writer", "report_ids" => packet["report_ids"], "overrides" => []}
  defp ensure!(true, _message), do: :ok
  defp ensure!(false, message), do: raise(message)
end
