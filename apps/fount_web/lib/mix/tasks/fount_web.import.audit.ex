defmodule Mix.Tasks.FountWeb.Import.Audit do
  @moduledoc "Prints source-bound import diagnostics and call summaries without dispatching inference."
  use Mix.Task
  alias Ecto.Adapters.SQL

  @shortdoc "Shows import parser/assessment audit for an owned project key"
  def run([key]) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    if is_nil(Process.whereis(Fount.Repo)), do: Fount.Repo.start_link()
    owner = Application.fetch_env!(:fount_web, :owner)[:id]
    {:ok, project} = FountWeb.Store.project_by_key(Fount.Repo, owner, key)
    {:ok, screenplay} = Fount.Persistence.load(Fount.Repo, key)

    {:ok, inventory} =
      FountWeb.SemanticStore.assessment_for_revision(
        Fount.Repo,
        owner,
        project["id"],
        screenplay.revision.id
      )

    history =
      FountWeb.SemanticStore.assessment_history(
        Fount.Repo,
        owner,
        project["id"],
        screenplay.revision.id
      )

    calls =
      SQL.query!(
        Fount.Repo,
        """
        SELECT pr.run_id::text,pr.status,pr.request_snapshot->>'purpose' AS purpose,
               pr.request_snapshot->>'provider' AS provider,pr.request_snapshot->>'model' AS requested_model,
               pr.request_snapshot->>'reasoning_effort' AS reasoning_effort,
               pr.response->>'model' AS returned_model,pr.provider_request_id,pr.error_category,
               pr.request_fingerprint,pr.dispatched_at::text,pr.responded_at::text,pr.usage
        FROM fount_run_provider_requests pr
        JOIN fount_web_runs wr ON wr.run_id=pr.run_id
        WHERE wr.project_id=$1::text::uuid AND wr.owner_id=$2
        ORDER BY pr.intended_at,pr.id
        """,
        [project["id"], owner],
        log: false
      )

    audit = inventory["result"]["import_audit"] || %{}

    summary = %{
      project_key: key,
      revision_id: screenplay.revision.id,
      source_sha256: inventory["source_sha256"],
      parser_audit: Map.drop(audit, ["decisions"]),
      parser_decision_count: length(audit["decisions"] || []),
      assessments:
        Enum.map(
          history,
          &Map.take(&1, ~w(id origin status prompt_version model run_id coverage error))
        ),
      calls: Enum.map(calls.rows, &Map.new(Enum.zip(calls.columns, &1)))
    }

    Mix.shell().info(Jason.encode!(summary, pretty: true))
  end

  def run(_), do: Mix.raise("Usage: mix fount_web.import.audit PROJECT_KEY")
end
