defmodule Mix.Tasks.FountWeb.Import.Audit do
  @moduledoc "Source-bound, read-only import diagnosis. Default output omits raw requests and response bodies."
  use Mix.Task
  alias Ecto.Adapters.SQL
  alias Fount.Screenplay.Model
  alias Fount.Semantics.SourceInventory
  alias FountWeb.{SemanticContext, SemanticStore, Store}
  alias FountWorkshop.Writing.Completion

  @shortdoc "Import audit: PROJECT_KEY [--cue ELEMENT_ID] [--json] [--evidence]"
  def run(args) do
    case OptionParser.parse(args, strict: [cue: :string, json: :boolean, evidence: :boolean]) do
      {opts, [key], []} ->
        audit(key, opts)

      _ ->
        Mix.raise(
          "Usage: mix fount_web.import.audit PROJECT_KEY [--cue ELEMENT_ID] [--json] [--evidence]"
        )
    end
  end

  defp audit(key, opts) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    if is_nil(Process.whereis(Fount.Repo)), do: Fount.Repo.start_link()
    owner = Application.fetch_env!(:fount_web, :owner)[:id]

    with {:ok, project} <- Store.project_by_key(Fount.Repo, owner, key),
         {:ok, screenplay} <- Fount.Persistence.load(Fount.Repo, key) do
      summary = build_summary(owner, project, screenplay, opts)
      Mix.shell().info(Jason.encode!(summary, pretty: not opts[:json]))
    else
      {:error, reason} -> Mix.raise("Owned import unavailable: #{inspect(reason)}")
    end
  end

  defp build_summary(owner, project, screenplay, opts) do
    inventory = screenplay |> SourceInventory.build() |> Model.plain()

    history =
      SemanticStore.assessment_history(Fount.Repo, owner, project["id"], screenplay.revision.id)

    assessment =
      case SemanticStore.resolved_assessment_for_revision(
             Fount.Repo,
             owner,
             project["id"],
             screenplay.revision.id
           ) do
        {:ok, row} -> row
        {:error, :not_found} -> %{}
      end

    rows = if assessment["id"], do: SemanticStore.entities(Fount.Repo, assessment["id"]), else: []

    revision_rows =
      SemanticStore.entity_rows_for_revision(
        Fount.Repo,
        owner,
        project["id"],
        screenplay.revision.id
      )

    reviews =
      SemanticStore.review_history_for_revision(
        Fount.Repo,
        owner,
        project["id"],
        screenplay.revision.id
      )

    entities =
      rows
      |> SemanticContext.select_entity_rows(revision_rows, reviews)
      |> SemanticContext.project_entities(reviews)

    people = SemanticContext.character_profiles(entities, screenplay, inventory)
    calls = calls(owner, project["id"])
    audit = inventory["import_audit"]

    %{
      project_key: project["key"],
      revision_id: screenplay.revision.id,
      source_sha256: audit["source_sha256"],
      visible_source_sha256: audit["visible_source_sha256"],
      parser_audit: Map.drop(audit, ["decisions"]),
      parser_decision_count: length(audit["decisions"]),
      person_profiles: length(people),
      source_cue_groups:
        length(SemanticContext.cue_groups(inventory, revision_rows, assessment["result"] || %{})),
      assessments:
        Enum.map(
          history,
          &Map.take(
            &1,
            ~w(id origin status schema_version prompt_version model run_id coverage error)
          )
        ),
      calls: Enum.map(calls, &Map.drop(&1, ~w(response request_snapshot))),
      cue_explanation:
        explain_cue(
          opts[:cue],
          inventory,
          assessment,
          calls,
          reviews,
          people,
          revision_rows,
          opts
        )
    }
  end

  defp calls(owner, project_id) do
    result =
      SQL.query!(
        Fount.Repo,
        """
        SELECT pr.id::text AS request_id,pr.run_id::text,pr.step_id::text,s.stage,pr.status,
               pr.request_snapshot->>'purpose' AS purpose,pr.request_snapshot->>'model' AS requested_model,
               pr.response->>'model' AS returned_model,pr.error_category,pr.validation_result,
               pr.dispatched_at::text,pr.responded_at::text,pr.usage,pr.response,pr.request_snapshot
        FROM fount_run_provider_requests pr
        JOIN fount_run_steps s ON s.id=pr.step_id
        JOIN fount_web_runs wr ON wr.run_id=pr.run_id
        WHERE wr.project_id=$1::text::uuid AND wr.owner_id=$2
        ORDER BY pr.intended_at,pr.id
        """,
        [project_id, owner],
        log: false
      )

    Enum.map(result.rows, &Map.new(Enum.zip(result.columns, &1)))
  end

  defp explain_cue(nil, _inventory, _assessment, _calls, _reviews, _people, _rows, _opts), do: nil

  defp explain_cue(id, inventory, assessment, calls, reviews, people, rows, opts) do
    cue =
      Enum.find(inventory["character_cues"], &(&1["element_id"] == id)) ||
        Mix.raise("Cue ID does not belong to this owned source revision")

    result = assessment["result"] || %{}
    decision = Enum.find(result["cue_decisions"] || [], &(&1["literal_element_id"] == id))

    profiles =
      Enum.filter(
        people,
        &Enum.any?(&1.occurrences, fn occurrence -> occurrence.element_id == id end)
      )

    handles =
      rows
      |> Enum.filter(fn row ->
        get_in(row, ["payload", "element_id"]) == id or
          Enum.any?(get_in(row, ["payload", "occurrences"]) || [], &(&1["element_id"] == id))
      end)
      |> Enum.map(& &1["handle_id"])

    %{
      element_id: id,
      source_span: cue["source_span"],
      context: cue["context"],
      parser_decision:
        Enum.find(inventory["import_audit"]["decisions"], &(&1["element_id"] == id)),
      decision: redact_evidence(decision, opts),
      calls: Enum.flat_map(calls, &cue_call(&1, id, opts)),
      relations:
        Enum.filter(result["relations"] || [], fn relation ->
          decision && decision["entity_id"] in relation["members"]
        end),
      human_reviews: Enum.filter(reviews, &(&1["target_handle_id"] in handles)),
      effective_profiles:
        Enum.map(
          profiles,
          &Map.take(&1, [
            :id,
            :display_name,
            :review_state,
            :speaking_occurrences,
            :presence_occurrences
          ])
        )
    }
  end

  defp cue_call(call, id, opts) do
    response = call["response"] || %{}
    object = response["object"] || decode_text(response["text"])
    decision = response_cue_decision(object, id)
    prompt = get_in(call, ["request_snapshot", "prompt"]) || ""

    if decision || String.contains?(prompt, id),
      do: [
        %{
          request_id: call["request_id"],
          run_id: call["run_id"],
          step_id: call["step_id"],
          purpose: call["purpose"],
          validation: call["validation_result"],
          decision: redact_evidence(decision, opts)
        }
      ],
      else: []
  end

  defp response_cue_decision(object, id) when is_map(object) do
    case object["cue_decisions"] do
      rows when is_list(rows) -> Enum.find(rows, &(is_map(&1) and &1["literal_element_id"] == id))
      _ -> nil
    end
  end

  defp response_cue_decision(_, _id), do: nil

  defp decode_text(text) when is_binary(text) do
    case Completion.decode(text) do
      {:ok, object} -> object
      _ -> %{}
    end
  end

  defp decode_text(_), do: %{}
  defp redact_evidence(nil, _opts), do: nil

  defp redact_evidence(row, opts),
    do: if(opts[:evidence], do: row, else: Map.delete(row, "evidence"))
end
