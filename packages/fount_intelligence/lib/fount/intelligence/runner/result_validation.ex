defmodule Fount.Intelligence.Runner.ResultValidation do
  @moduledoc "Validates returned report evidence against explicit current/historical source models before exposing a public result."
  alias Fount.Intelligence.Reporting.Report

  def finish(%Report{} = report, current, opts) do
    models = [current | report.transient_models ++ Keyword.get(opts, :models, [])]
    sources = Map.new(models, &{{&1.id, &1.revision.id}, &1})
    resolver = fn screenplay_id, revision_id, target ->
      if screenplay_id == report.screenplay_id and revision_id in report.source_revision_ids do
        with {:ok, source} <- source(sources, screenplay_id, revision_id, opts),
             true <- source.id == screenplay_id and source.revision.id == revision_id,
             {:ok, node} <- Fount.Target.resolve(source, target),
             text when is_binary(text) <- Map.get(node, :text) do
          {:ok, text}
        else
          _ -> {:error, :source_mismatch}
        end
      else
        {:error, :unlisted_source}
      end
    end
    with true <- report.screenplay_id == current.id and report.primary_revision_id in report.source_revision_ids,
         {:ok, registry} <- Fount.SourceEvidence.validate(report.evidence, resolver),
         :ok <- Fount.SourceEvidence.citations(Report.citations(%{"findings" => report.findings,
           "data" => report.data, "annotations" => report.annotations, "graph" => report.graph}), registry) do
      {:ok, report}
    else
      _ -> {:error, :invalid_report_evidence}
    end
  rescue
    _ -> {:error, :invalid_report_evidence}
  end

  defp source(sources, sid, rid, opts) do
    case sources[{sid, rid}] do
      nil -> case opts[:history_reader] do
        reader when is_function(reader, 2) -> reader.(sid, rid)
        _ -> {:error, :missing_source_model}
      end
      model -> {:ok, model}
    end
  end
end
