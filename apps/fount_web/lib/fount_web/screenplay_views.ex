defmodule FountWeb.ScreenplayViews do
  @moduledoc "Owner-authorized Run-bound screenplay identity resolution for the read-only viewer."

  alias Ecto.Adapters.SQL
  alias Fount.Persistence

  @accepted_limit 20
  @evidence_limit 40

  def options(repo, access, run, progress)
      when is_map(access) and is_map(run) and is_map(progress) do
    with :ok <- verify_run_binding(access, run) do
      base = base_option(run)
      candidates = candidate_options(repo, run, progress)
      accepted = accepted_options(repo, run)
      evidence = evidence_options(repo, run, progress)
      {:ok, [base | candidates ++ accepted ++ evidence] |> Enum.reject(&is_nil/1)}
    end
  end

  def load(repo, access, run, progress, token) do
    with {:ok, options} <- options(repo, access, run, progress),
         {:ok, selected} <- selected_option(options, token),
         {:ok, screenplay} <- load_selected(repo, access["screenplay_id"], selected) do
      {:ok, %{selection: selected, screenplay: screenplay, options: options}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def token(%{kind: :base, revision_id: revision_id}), do: "base:#{revision_id}"

  def token(%{kind: :candidate, candidate_id: candidate_id, revision_id: revision_id}),
    do: "candidate:#{candidate_id}:#{revision_id}"

  def token(%{kind: :accepted, revision_id: revision_id}), do: "accepted:#{revision_id}"

  def token(%{kind: :evidence, analysis_run_id: analysis_run_id, revision_id: revision_id}),
    do: "evidence:#{analysis_run_id}:#{revision_id}"

  defp verify_run_binding(%{"screenplay_id" => screenplay_id}, %{"screenplay_id" => screenplay_id}),
       do: :ok

  defp verify_run_binding(_, _), do: {:error, :run_screenplay_mismatch}

  defp base_option(run) do
    case get_in(run, ["plan", "base_revision_id"]) do
      revision_id when is_binary(revision_id) ->
        option(:base, revision_id, "Run base")

      _ ->
        nil
    end
  end

  defp candidate_options(repo, run, progress) do
    selected_id = run["selected_candidate_id"]
    screenplay_id = run["screenplay_id"]

    candidate_ids =
      [selected_id]
      |> Kernel.++(step_candidate_ids(progress))
      |> Kernel.++(decision_candidate_ids(progress))
      |> Kernel.++(delivery_candidate_ids(progress))
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    Enum.flat_map(candidate_ids, &candidate_option(repo, &1, screenplay_id, selected_id))
  end

  defp candidate_option(repo, candidate_id, screenplay_id, selected_id) do
    case SQL.query(
           repo,
           "SELECT result_revision_id::text,base_revision_id::text FROM writing_candidates WHERE id=$1::text::uuid AND screenplay_id=$2::text::uuid",
           [candidate_id, screenplay_id],
           log: false
         ) do
      {:ok, %{rows: [_]} = result} ->
        [candidate] = rows(result)
        label = if candidate_id == selected_id, do: "Selected candidate", else: "Run candidate"

        [
          %{
            kind: :candidate,
            candidate_id: candidate_id,
            revision_id: candidate["result_revision_id"],
            label: label,
            status: candidate["status"] || "candidate",
            base_revision_id: candidate["base_revision_id"]
          }
          |> put_token()
        ]

      _ ->
        []
    end
  end

  defp accepted_options(repo, run) do
    case SQL.query(
           repo,
           "SELECT result_revision_id::text,candidate_id::text,inserted_at FROM acceptances WHERE screenplay_id=$1::text::uuid AND run_id=$2::text::uuid AND acceptance_kind='approved' ORDER BY inserted_at DESC,id DESC LIMIT $3",
           [run["screenplay_id"], run["id"], @accepted_limit],
           log: false
         ) do
      {:ok, result} ->
        result
        |> rows()
        |> Enum.map(fn row ->
          %{
            kind: :accepted,
            revision_id: row["result_revision_id"],
            candidate_id: row["candidate_id"],
            label: "Accepted revision",
            status: "accepted"
          }
          |> put_token()
        end)

      {:error, _} ->
        []
    end
  end

  defp evidence_options(repo, run, progress) do
    bound_revisions = candidate_options(repo, run, progress) |> Enum.map(& &1.revision_id)
    lineage = FountWeb.AnalysisDashboard.lineage(progress, run)
    lineage = Map.update!(lineage, :revision_ids, &Enum.uniq(&1 ++ bound_revisions))

    statement = """
    SELECT id::text,revision_id::text,session_id::text,candidate_id::text,status,playbook,result
    FROM analysis_runs
    WHERE screenplay_id=$1::text::uuid
      AND (
        id::text = ANY($2::text[]) OR
        session_id::text = ANY($3::text[]) OR
        candidate_id::text = ANY($4::text[]) OR
        (session_id IS NULL AND candidate_id IS NULL AND revision_id::text = ANY($5::text[]))
      )
    ORDER BY inserted_at DESC,id DESC
    LIMIT $6
    """

    case SQL.query(
           repo,
           statement,
           [
             run["screenplay_id"],
             lineage.analysis_run_ids,
             lineage.session_ids,
             lineage.candidate_ids,
             lineage.revision_ids,
             @evidence_limit
           ],
           log: false
         ) do
      {:ok, result} ->
        result
        |> rows()
        |> Enum.flat_map(&evidence_row_options(&1, run["screenplay_id"]))

      {:error, _} ->
        []
    end
  end

  defp evidence_row_options(row, screenplay_id) do
    Enum.map(recorded_evidence_revisions(row, screenplay_id), fn revision_id ->
      %{
        kind: :evidence,
        analysis_run_id: row["id"],
        revision_id: revision_id,
        candidate_id: row["candidate_id"],
        session_id: row["session_id"],
        label: "Analysis evidence · #{row["playbook"] || "unknown playbook"}",
        status: row["status"] || "evidence"
      }
      |> put_token()
    end)
  end

  defp recorded_evidence_revisions(row, screenplay_id) do
    references =
      row
      |> get_in(["result", "evidence"])
      |> List.wrap()
      |> Enum.filter(&evidence_screenplay?(&1, screenplay_id))
      |> Enum.map(fn evidence ->
        evidence["revision_id"] || get_in(evidence, ["target", "revision_id"])
      end)

    [row["revision_id"] | references] |> Enum.filter(&is_binary/1) |> Enum.uniq()
  end

  defp evidence_screenplay?(evidence, screenplay_id) do
    recorded = evidence["screenplay_id"] || get_in(evidence, ["target", "screenplay_id"])
    recorded in [nil, screenplay_id]
  end

  defp step_candidate_ids(progress) do
    progress
    |> Map.get("steps", [])
    |> List.wrap()
    |> Enum.flat_map(fn step ->
      result = step["result"] || %{}
      List.wrap(result["candidate_id"]) ++ List.wrap(result["candidate_ids"])
    end)
  end

  defp decision_candidate_ids(progress),
    do: progress |> Map.get("decisions", []) |> List.wrap() |> Enum.map(& &1["candidate_id"])

  defp delivery_candidate_ids(progress),
    do: progress |> Map.get("deliveries", []) |> List.wrap() |> Enum.map(& &1["candidate_id"])

  defp option(kind, revision_id, label) do
    %{kind: kind, revision_id: revision_id, label: label, status: Atom.to_string(kind)}
    |> put_token()
  end

  defp put_token(option), do: Map.put(option, :token, token(option))

  defp selected_option([], _token), do: {:error, :no_bound_revision}
  defp selected_option([first | _], token) when token in [nil, ""], do: {:ok, first}

  defp selected_option(options, token) when is_binary(token) do
    case Enum.find(options, &(&1.token == token)) do
      nil -> {:error, :stale_or_unbound_revision}
      option -> {:ok, option}
    end
  end

  defp selected_option(_, _), do: {:error, :stale_or_unbound_revision}

  defp load_selected(repo, screenplay_id, %{kind: :evidence} = selected) do
    statement =
      "SELECT 1 FROM analysis_runs WHERE id=$1::text::uuid AND screenplay_id=$2::text::uuid AND revision_id=$3::text::uuid"

    direct =
      SQL.query(repo, statement, [selected.analysis_run_id, screenplay_id, selected.revision_id],
        log: false
      )

    if match?({:ok, %{rows: [[1]]}}, direct) or recorded_revision?(repo, screenplay_id, selected) do
      load_evidence_revision(repo, screenplay_id, selected.revision_id)
    else
      {:error, :stale_or_unbound_revision}
    end
  end

  defp load_selected(repo, screenplay_id, %{kind: :candidate} = selected) do
    with {:ok, candidate} <- Persistence.candidate(repo, selected.candidate_id),
         true <- candidate["screenplay_id"] == screenplay_id,
         true <- candidate["result_revision_id"] == selected.revision_id do
      {:ok, candidate["screenplay"]}
    else
      false -> {:error, :candidate_identity_mismatch}
      {:error, :not_found} -> {:error, :candidate_not_found}
    end
  end

  defp load_selected(repo, screenplay_id, %{revision_id: revision_id}) do
    case Persistence.load_revision(repo, screenplay_id, revision_id) do
      {:ok, screenplay} -> {:ok, screenplay}
      {:error, :not_found} -> {:error, :revision_not_found}
    end
  end

  defp recorded_revision?(repo, screenplay_id, selected) do
    case SQL.query(
           repo,
           "SELECT revision_id::text,result FROM analysis_runs WHERE id=$1::text::uuid AND screenplay_id=$2::text::uuid",
           [selected.analysis_run_id, screenplay_id],
           log: false
         ) do
      {:ok, %{rows: [_]} = result} ->
        [row] = rows(result)
        selected.revision_id in recorded_evidence_revisions(row, screenplay_id)

      _ ->
        false
    end
  end

  defp load_evidence_revision(repo, screenplay_id, revision_id) do
    case Persistence.load_revision(repo, screenplay_id, revision_id) do
      {:ok, screenplay} -> {:ok, screenplay}
      {:error, :not_found} -> {:error, :revision_not_found}
    end
  end

  defp rows(%{columns: columns, rows: rows}) do
    Enum.map(rows, fn values -> columns |> Enum.zip(values) |> Map.new() end)
  end
end
