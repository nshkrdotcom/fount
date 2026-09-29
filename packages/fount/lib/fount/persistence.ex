defmodule Fount.Persistence do
  @moduledoc "Immutable PostgreSQL revisions and explicit writer decisions for screenplays."
  alias Ecto.Adapters.SQL
  alias Fount.ID
  alias Fount.Persistence.Codec
  alias Fount.Screenplay
  alias Fount.Screenplay.Model
  alias Fount.Writing.{Approval, Authority, CanonicalJSON, CheckSet, Review, ReviewGate}
  alias Fount.Writing.UTF8Span

  def migrations_path, do: Application.app_dir(:fount, "priv/repo/migrations")

  def create(repo, key, %Screenplay{} = root, opts \\ []) do
    root = Model.refresh(root)

    with :ok <- validate(root),
         true <- is_nil(root.revision.parent_id) do
      transaction(repo, fn -> create_root(repo, key, root, opts) end)
    else
      false -> {:error, :root_has_parent}
      error -> error
    end
  end

  defp create_root(repo, key, root, opts) do
    if one(repo, "SELECT id FROM screenplays WHERE key=$1", [key]), do: rollback(repo, :key_taken)
    q(repo, "INSERT INTO screenplays(id,key) VALUES($1::uuid,$2)", [root.id, key])
    insert_revision(repo, root)
    acceptance(repo, root, nil, acceptance_details(opts))
    set_head(repo, root.id, root.revision.id)
    root
  end

  @doc "Legacy save entry point. Canon-changing calls must use a saved candidate plus authorized approval."
  def save(repo, key, %Screenplay{} = model, opts \\ []),
    do: save_edit(repo, key, model, opts)

  @doc "Rejects post-genesis direct canon changes; unchanged heads remain an idempotent check."
  def save_edit(repo, key, %Screenplay{} = candidate, opts \\ []) do
    candidate = Model.refresh(candidate)

    with :ok <- validate(candidate) do
      transaction(repo, fn -> reject_direct_edit(repo, key, candidate, opts) end)
    end
  end

  defp reject_direct_edit(repo, key, candidate, opts) do
    row =
      one(repo, "SELECT id,head_revision_id FROM screenplays WHERE key=$1 FOR UPDATE", [key]) ||
        rollback(repo, :not_found)

    if row["id"] != candidate.id, do: rollback(repo, :wrong_screenplay)
    actual = row["head_revision_id"]
    expected = Keyword.get(opts, :expected_revision, candidate.revision.parent_id || candidate.revision.id)
    if actual != expected, do: rollback(repo, {:stale_revision, actual})

    if candidate.revision.id == actual do
      insert_revision(repo, candidate)
      candidate
    else
      if candidate.revision.parent_id != actual, do: rollback(repo, :wrong_parent)
      rollback(repo, :approval_required)
    end
  end

  @doc "Stores a manual edit as an unaccepted writing candidate without advancing canon."
  def save_edit_candidate(repo, key, %Screenplay{} = candidate, opts \\ []) do
    candidate = Model.refresh(candidate)

    with :ok <- validate(candidate) do
      transaction(repo, fn -> persist_manual_candidate(repo, key, candidate, opts) end)
    end
  end

  defp persist_manual_candidate(repo, key, candidate, opts) do
    row =
      one(repo, "SELECT id,head_revision_id FROM screenplays WHERE key=$1 FOR UPDATE", [key]) ||
        rollback(repo, :not_found)

    if row["id"] != candidate.id, do: rollback(repo, :wrong_screenplay)
    base_id = Keyword.get(opts, :expected_revision, candidate.revision.parent_id)
    if row["head_revision_id"] != base_id, do: rollback(repo, {:stale_revision, row["head_revision_id"]})
    if candidate.revision.id == base_id, do: rollback(repo, :candidate_contains_no_change)
    if candidate.revision.parent_id != base_id, do: rollback(repo, :wrong_parent)

    constraints = Keyword.get(opts, :constraints, [])
    session_id = Keyword.get(opts, :session_id, ID.v4())

    session =
      persist_session(
        repo,
        %{
          id: session_id,
          screenplay_id: candidate.id,
          base_revision_id: base_id,
          workflow: "pass",
          request: %{
            "operation" => "manual_edit",
            "constraints" => Model.plain(constraints),
            "approval" => Model.plain(Keyword.get(opts, :approval, %{}))
          },
          status: "review_ready",
          provenance: %{"origin" => "direct_manual_edit"}
        },
        session_id,
        nil
      )

    persist_candidate(
      repo,
      field(session, :id),
      %{
        id: Keyword.get(opts, :candidate_id),
        screenplay: candidate,
        label: Keyword.get(opts, :label, "Manual edit"),
        strategy: %{"source" => "manual_edit"},
        change_groups: [
          %{
            "id" => "manual-edit",
            "operations" => Model.plain(Keyword.get(opts, :operations, []))
          }
        ],
        lineage: [],
        provenance: %{
          "checks" => Model.plain(Keyword.get(opts, :checks, [])),
          "report_ids" => Keyword.get(opts, :report_ids, []),
          "constraints" => Model.plain(constraints),
          "origin" => "writer_edit"
        }
      },
      candidate,
      nil
    )
  end

  def load(repo, key) do
    case one(repo, "SELECT id,head_revision_id FROM screenplays WHERE key=$1", [key]) do
      nil -> {:error, :not_found}
      row -> load_revision(repo, row["id"], row["head_revision_id"])
    end
  end

  def load_revision(repo, screenplay_id, revision_id) do
    case one(repo, "SELECT model,artifact_id FROM revisions WHERE screenplay_id=$1::uuid AND id=$2::uuid", [
           screenplay_id,
           revision_id
         ]) do
      nil ->
        {:error, :not_found}

      row ->
        model = Codec.decode(row["model"])

        import =
          if row["artifact_id"] do
            artifact =
              one(
                repo,
                "SELECT id,format,original_bytes,render_hash,fidelity FROM import_artifacts WHERE screenplay_id=$1::uuid AND id=$2::uuid",
                [screenplay_id, row["artifact_id"]]
              )

            %{
              id: artifact["id"],
              format: String.to_existing_atom(artifact["format"]),
              bytes: artifact["original_bytes"],
              render_hash: artifact["render_hash"],
              losses: artifact["fidelity"]["losses"] || [],
              revision_id: revision_id
            }
          end

        {:ok, %{model | import: import}}
    end
  end

  def at_revision(repo, revision_id) do
    case one(repo, "SELECT screenplay_id FROM revisions WHERE id=$1::uuid", [revision_id]) do
      nil -> {:error, :not_found}
      row -> load_revision(repo, row["screenplay_id"], revision_id)
    end
  end

  def history(repo, screenplay_id, opts \\ []) do
    id =
      case one(repo, "SELECT id FROM screenplays WHERE id=$1::uuid OR key=$2", [
             if(uuid?(screenplay_id), do: screenplay_id, else: ID.v4()),
             screenplay_id
           ]) do
        nil -> nil
        row -> row["id"]
      end

    if id do
      limit = min(max(Keyword.get(opts, :limit, 50), 1), 500)

      head =
        Keyword.get(opts, :head) ||
          one(repo, "SELECT head_revision_id FROM screenplays WHERE id=$1::uuid", [id])["head_revision_id"]

      rows =
        all(
          repo,
          "WITH RECURSIVE chain AS (SELECT id,parent_id,inserted_at,actor,message,content_hash,render_hash,0 AS depth FROM revisions WHERE screenplay_id=$1::uuid AND id=$2::uuid UNION ALL SELECT r.id,r.parent_id,r.inserted_at,r.actor,r.message,r.content_hash,r.render_hash,c.depth+1 FROM revisions r JOIN chain c ON r.id=c.parent_id WHERE r.screenplay_id=$1::uuid) SELECT * FROM chain ORDER BY depth LIMIT $3",
          [id, head, limit]
        )

      Enum.map(rows, fn row ->
        %Fount.Revision{
          id: row["id"],
          parent_id: row["parent_id"],
          created_at: row["inserted_at"],
          actor: row["actor"],
          message: row["message"],
          content_hash: row["content_hash"],
          render_hash: row["render_hash"]
        }
      end)
    else
      []
    end
  end

  @doc "Creates or optimistically updates a durable writing session."
  def save_session(repo, session) when is_map(session), do: save_session(repo, session, [])

  @doc "Creates/updates a session with an optional transaction-local write guard."
  def save_session(repo, session, opts) when is_map(session) and is_list(opts) do
    id = field(session, :id) || ID.v4()
    operation_key = field(session, :operation_key) || Keyword.get(opts, :operation_key)

    transaction(repo, fn ->
      :ok = guarded_write(repo, opts, :session, %{id: id, operation_key: operation_key})
      persist_session(repo, session, id, operation_key)
    end)
  end

  defp persist_session(repo, session, id, operation_key) do
    previous =
      if is_binary(operation_key) do
        one(repo, "SELECT * FROM writing_sessions WHERE operation_key=$1 FOR UPDATE", [operation_key])
      else
        one(repo, "SELECT * FROM writing_sessions WHERE id=$1::uuid FOR UPDATE", [id])
      end

    case previous do
      nil -> insert_session(repo, session, id, operation_key)
      previous -> update_session(repo, session, previous, operation_key)
    end
  end

  defp update_session(repo, session, previous, operation_key) do
    id = previous["id"]

    if not session_identity_matches?(previous, session, operation_key),
      do: rollback(repo, :immutable_session_fields)

    case session_lock_action(previous, session, operation_key) do
      :replay ->
        previous

      :stale ->
        rollback(repo, :stale_session)

      :update ->
        next = previous["lock_version"] + 1

        q(
          repo,
          "UPDATE writing_sessions SET status=$2,strategies=$3::jsonb,progress=$4::jsonb,provenance=$5::jsonb,lock_version=$6,updated_at=now() WHERE id=$1::uuid",
          [
            id,
            field(session, :status) || previous["status"],
            json(field(session, :strategies) || previous["strategies"]),
            json(field(session, :progress) || previous["progress"]),
            json(field(session, :provenance) || previous["provenance"]),
            next
          ]
        )

        session
        |> Map.drop(["id", "lock_version"])
        |> Map.put(:operation_key, operation_key)
        |> Map.put(:lock_version, next)
        |> Map.put(:id, id)
    end
  end

  defp session_lock_action(previous, session, operation_key) do
    supplied_lock = field(session, :lock_version)

    cond do
      is_nil(supplied_lock) and is_binary(operation_key) -> :replay
      is_nil(supplied_lock) or previous["lock_version"] != supplied_lock -> :stale
      true -> :update
    end
  end

  defp session_identity_matches?(previous, session, operation_key) do
    previous["screenplay_id"] == field(session, :screenplay_id) and
      previous["base_revision_id"] == field(session, :base_revision_id) and
      previous["request"] == field(session, :request) and
      previous["operation_key"] == operation_key
  end

  defp insert_session(repo, session, id, operation_key) do
    screenplay_id = field(session, :screenplay_id)
    base_id = field(session, :base_revision_id)

    ensure_session_base!(repo, screenplay_id, base_id)

    result =
      q(
        repo,
        "INSERT INTO writing_sessions(id,screenplay_id,base_revision_id,workflow,status,request,strategies,progress,provenance,operation_key) VALUES($1::uuid,$2::uuid,$3::uuid,$4,$5,$6::jsonb,$7::jsonb,$8::jsonb,$9::jsonb,$10) ON CONFLICT(operation_key) WHERE operation_key IS NOT NULL DO NOTHING",
        [
          id,
          screenplay_id,
          base_id,
          field(session, :workflow),
          field(session, :status) || "open",
          json(field(session, :request) || %{}),
          json(field(session, :strategies) || []),
          json(field(session, :progress) || %{}),
          json(field(session, :provenance) || %{}),
          operation_key
        ]
      )

    if result.num_rows == 0 and is_binary(operation_key) do
      previous =
        one(repo, "SELECT * FROM writing_sessions WHERE operation_key=$1 FOR UPDATE", [operation_key]) ||
          rollback(repo, :session_operation_conflict)

      update_session(repo, session, previous, operation_key)
    else
      session
      |> Map.drop(["id", "lock_version"])
      |> Map.put(:operation_key, operation_key)
      |> Map.put(:id, id)
      |> Map.put(:lock_version, 1)
    end
  end

  defp ensure_session_base!(repo, screenplay_id, base_id) do
    unless one(repo, "SELECT id FROM revisions WHERE screenplay_id=$1::uuid AND id=$2::uuid", [screenplay_id, base_id]),
      do: rollback(repo, :unknown_base)
  end

  @doc "Looks up the idempotent session opened for an external operation key."
  def session_by_operation(repo, operation_key) when is_binary(operation_key) do
    case one(repo, "SELECT * FROM writing_sessions WHERE operation_key=$1", [operation_key]) do
      nil -> {:error, :not_found}
      row -> {:ok, row}
    end
  end

  @doc "Saves an immutable candidate revision without changing the accepted head."
  def save_candidate(repo, session_id, candidate) when is_map(candidate),
    do: save_candidate(repo, session_id, candidate, [])

  @doc "Saves a candidate with optional operation identity and transaction-local write guard."
  def save_candidate(repo, session_id, candidate, opts) when is_map(candidate) and is_list(opts) do
    model = field(candidate, :screenplay) |> Model.refresh()
    operation_key = field(candidate, :operation_key) || Keyword.get(opts, :operation_key)

    with :ok <- validate(model) do
      transaction(repo, fn ->
        :ok = guarded_write(repo, opts, :candidate, %{session_id: session_id, operation_key: operation_key})
        persist_candidate(repo, session_id, candidate, model, operation_key)
      end)
    end
  end

  defp persist_candidate(repo, session_id, candidate, model, operation_key) do
    session = candidate_session(repo, session_id, model)
    snapshot = candidate_check_snapshot(repo, session, candidate)
    id = field(candidate, :id) || ID.v4()

    previous =
      if is_binary(operation_key) do
        one(repo, "SELECT * FROM writing_candidates WHERE operation_key=$1", [operation_key])
      else
        one(repo, "SELECT * FROM writing_candidates WHERE id=$1::uuid", [id])
      end

    case previous do
      nil -> insert_candidate(repo, session_id, candidate, model, id, snapshot, operation_key)
      previous -> verify_candidate_identity(repo, candidate, model, previous["id"], previous, snapshot, operation_key)
    end
  end

  defp candidate_session(repo, session_id, model) do
    session =
      one(repo, "SELECT * FROM writing_sessions WHERE id=$1::uuid FOR SHARE", [session_id]) ||
        rollback(repo, :unknown_session)

    if session["screenplay_id"] != model.id or session["base_revision_id"] != model.revision.parent_id,
      do: rollback(repo, :wrong_base)

    session
  end

  defp candidate_check_snapshot(repo, session, candidate) do
    provenance = Model.plain(field(candidate, :provenance) || %{})

    case CheckSet.snapshot(session, provenance) do
      {:ok, value} -> value
      {:error, reason} -> rollback(repo, reason)
    end
  end

  defp verify_candidate_identity(repo, candidate, model, id, previous, snapshot, operation_key) do
    existing =
      one(repo, "SELECT content_hash,render_hash,model FROM revisions WHERE id=$1::uuid", [
        previous["result_revision_id"]
      ])

    unless candidate_revision_matches?(previous, candidate, model, existing),
      do: rollback(repo, :candidate_identity_conflict)

    cond do
      is_nil(previous["check_set_fingerprint"]) and previous["required_checks"] in [nil, []] and
          previous["decision"] == "proposed" ->
        # Upgrade path for a pending candidate created before Phase 01. Only an
        # exact immutable candidate replay may attach the newly authoritative
        # check snapshot; no reviewed/accepted content is rewritten.
        q(
          repo,
          "UPDATE writing_candidates SET required_checks=$2::jsonb,check_set_fingerprint=$3 WHERE id=$1::uuid AND check_set_fingerprint IS NULL AND decision='proposed'",
          [id, json(snapshot["required_checks"]), snapshot["check_set_fingerprint"]]
        )

      is_nil(previous["check_set_fingerprint"]) ->
        rollback(repo, :candidate_identity_conflict)

      previous["required_checks"] != snapshot["required_checks"] or
          previous["check_set_fingerprint"] != snapshot["check_set_fingerprint"] ->
        rollback(repo, :candidate_identity_conflict)

      true ->
        :ok
    end

    candidate
    |> Map.put(:id, id)
    |> Map.put(:operation_key, operation_key)
  end

  defp candidate_revision_matches?(previous, candidate, model, existing) do
    previous["result_revision_id"] == model.revision.id and
      is_map(existing) and
      existing["content_hash"] == model.revision.content_hash and
      existing["render_hash"] == model.revision.render_hash and
      existing["model"] == Codec.encode(model) and
      candidate_payload(previous) == candidate_payload(candidate)
  end

  defp insert_candidate(repo, session_id, candidate, model, id, snapshot, operation_key) do
    insert_revision(repo, model)

    q(
      repo,
      "INSERT INTO writing_candidates(id,screenplay_id,session_id,base_revision_id,result_revision_id,parent_candidate_id,label,strategy,change_groups,lineage,provenance,required_checks,check_set_fingerprint,operation_key) VALUES($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::uuid,$6::uuid,$7,$8::jsonb,$9::jsonb,$10::jsonb,$11::jsonb,$12::jsonb,$13,$14)",
      [
        id,
        model.id,
        session_id,
        model.revision.parent_id,
        model.revision.id,
        field(candidate, :parent_candidate_id),
        field(candidate, :label) || "Candidate",
        json(field(candidate, :strategy) || %{}),
        json(field(candidate, :change_groups) || []),
        json(field(candidate, :lineage) || []),
        json(field(candidate, :provenance) || %{}),
        json(snapshot["required_checks"]),
        snapshot["check_set_fingerprint"],
        operation_key
      ]
    )

    q(repo, "UPDATE writing_candidates SET payload_hash=$2 WHERE id=$1::uuid", [
      id,
      CanonicalJSON.hash(candidate_payload(candidate))
    ])

    candidate
    |> Map.put(:id, id)
    |> Map.put(:operation_key, operation_key)
  end

  @doc "Loads a saved candidate and its actual revision value."
  def candidate(repo, id) do
    case one(repo, "SELECT * FROM writing_candidates WHERE id=$1::uuid", [id]) do
      nil ->
        {:error, :not_found}

      row ->
        with {:ok, model} <- load_revision(repo, row["screenplay_id"], row["result_revision_id"]) do
          {:ok, Map.put(row, "screenplay", model)}
        end
    end
  end

  @doc "Looks up the immutable candidate saved for an external operation key."
  def candidate_by_operation(repo, operation_key) when is_binary(operation_key) do
    case one(repo, "SELECT id FROM writing_candidates WHERE operation_key=$1", [operation_key]) do
      nil -> {:error, :not_found}
      row -> candidate(repo, row["id"])
    end
  end

  def session(repo, id) do
    case one(repo, "SELECT * FROM writing_sessions WHERE id=$1::uuid", [id]) do
      nil -> {:error, :not_found}
      row -> {:ok, row}
    end
  end

  def candidates_for_session(repo, session_id) do
    all(repo, "SELECT id FROM writing_candidates WHERE session_id=$1::uuid ORDER BY inserted_at,id", [session_id])
    |> Enum.map(fn row ->
      {:ok, candidate} = candidate(repo, row["id"])
      candidate
    end)
  end

  @doc "Accepts one exactly reviewed candidate with trusted host authority and stable approval identity."
  def accept_candidate(repo, candidate_id, opts) when is_list(opts) do
    with {:ok, approval} <- normalize_approval(Keyword.get(opts, :approval)),
         %Authority{} = authority <- Keyword.get(opts, :authority) do
      transaction(repo, fn -> accept_candidate_locked(repo, candidate_id, approval, authority) end)
    else
      nil -> {:error, :authorized_approval_required}
      {:error, _} = error -> error
      _ -> {:error, :invalid_authority}
    end
  end

  defp normalize_approval(%Approval{} = approval), do: approval |> Approval.to_map() |> Approval.from_map()
  defp normalize_approval(map) when is_map(map), do: Approval.from_map(map)
  defp normalize_approval(_), do: {:error, :authorized_approval_required}

  defp accept_candidate_locked(repo, candidate_id, approval, authority) do
    {screenplay, row} = lock_candidate(repo, candidate_id)
    context = acceptance_review(repo, candidate_id, row, approval, authority)
    permitted = permitted_report_sources(repo, row, context.model)

    Enum.each(context.stored["report_ids"], fn id ->
      verify_review_report(repo, id, row, context.model, permitted)
    end)

    finalize_candidate_acceptance(repo, candidate_id, screenplay, row, context)
  end

  defp lock_candidate(repo, candidate_id) do
    identity =
      one(repo, "SELECT screenplay_id FROM writing_candidates WHERE id=$1::uuid", [candidate_id]) ||
        rollback(repo, :not_found)

    # All direct Core acceptances take the screenplay lock first, then candidate.
    screenplay =
      one(
        repo,
        "SELECT id,head_revision_id FROM screenplays WHERE id=$1::uuid FOR UPDATE",
        [identity["screenplay_id"]]
      )

    row =
      one(
        repo,
        "SELECT c.*,r.content_hash FROM writing_candidates c JOIN revisions r ON r.screenplay_id=c.screenplay_id AND r.id=c.result_revision_id WHERE c.id=$1::uuid FOR UPDATE OF c",
        [candidate_id]
      ) || rollback(repo, :not_found)

    {screenplay, row}
  end

  defp acceptance_review(repo, candidate_id, row, approval, authority) do
    unless is_binary(row["check_set_fingerprint"]) and row["check_set_fingerprint"] != "",
      do: rollback(repo, :candidate_check_snapshot_missing)

    validate_approval_binding(repo, candidate_id, row, approval)
    authorize_approval(repo, row, approval, authority)

    {:ok, model} = load_revision(repo, row["screenplay_id"], row["result_revision_id"])
    stored = stored_review_candidate(candidate_id, row, model)

    case ReviewGate.validate(stored, approval.review, approval.approver) do
      :ok -> :ok
      {:error, reason} -> rollback(repo, reason)
    end

    %{
      approval: approval,
      approval_hash: Approval.fingerprint(approval),
      review_hash: Review.fingerprint(approval.review),
      model: model,
      stored: stored
    }
  end

  defp validate_approval_binding(repo, candidate_id, row, approval) do
    cond do
      approval.screenplay_id != row["screenplay_id"] -> rollback(repo, :approval_screenplay_mismatch)
      approval.candidate_id != candidate_id -> rollback(repo, :approval_candidate_mismatch)
      approval.base_revision_id != row["base_revision_id"] -> rollback(repo, :approval_base_mismatch)
      approval.content_hash != row["content_hash"] -> rollback(repo, :approval_content_mismatch)
      true -> :ok
    end
  end

  defp authorize_approval(repo, row, approval, authority) do
    case Authority.authorize(authority, :approve, row["screenplay_id"], approval.approver) do
      :ok -> :ok
      {:error, reason} -> rollback(repo, reason)
    end
  end

  defp stored_review_candidate(candidate_id, row, model) do
    checks = stored_checks(row["provenance"] || %{})

    %{
      "id" => candidate_id,
      "base_revision_id" => row["base_revision_id"],
      "content_hash" => row["content_hash"],
      "structural_errors" => Fount.Validate.screenplay(model),
      "checks" => checks,
      "required_checks" => row["required_checks"] || [],
      "check_set_fingerprint" => row["check_set_fingerprint"],
      "report_ids" => row["provenance"]["report_ids"] || []
    }
  end

  defp stored_checks(provenance) do
    checks = Map.get(provenance, "checks", [])
    application = Map.get(provenance, "application_checks", [])
    seen = MapSet.new(Enum.map(checks, &Map.get(&1, "constraint_id")))
    checks ++ Enum.reject(application, &MapSet.member?(seen, Map.get(&1, "constraint_id")))
  end

  defp permitted_report_sources(repo, row, model) do
    session =
      one(repo, "SELECT workflow,request FROM writing_sessions WHERE id=$1::uuid AND screenplay_id=$2::uuid", [
        row["session_id"],
        model.id
      ]) || rollback(repo, :candidate_session_mismatch)

    historical =
      if session["workflow"] == "recover",
        do: get_in(session["request"], ["options", "source_revision_id"]),
        else: nil

    historical =
      if is_binary(historical) and
           one(repo, "SELECT id FROM revisions WHERE screenplay_id=$1::uuid AND id=$2::uuid", [model.id, historical]),
         do: [historical],
         else: []

    MapSet.new([row["base_revision_id"], row["result_revision_id"] | historical])
  end

  defp verify_review_report(repo, id, row, model, permitted) do
    report =
      one(
        repo,
        "SELECT id,primary_revision_id,session_id FROM analysis_reports WHERE id=$1::uuid AND screenplay_id=$2::uuid",
        [id, model.id]
      )

    unless report, do: rollback(repo, :missing_review_report)

    sources =
      all(
        repo,
        "SELECT revision_id FROM analysis_report_sources WHERE screenplay_id=$1::uuid AND report_id=$2::uuid",
        [model.id, id]
      )

    unless (is_nil(report["session_id"]) or report["session_id"] == row["session_id"]) and
             MapSet.member?(permitted, report["primary_revision_id"]) and
             Enum.all?(sources, &MapSet.member?(permitted, &1["revision_id"])),
           do: rollback(repo, :report_lineage_mismatch)
  end

  defp finalize_candidate_acceptance(repo, candidate_id, screenplay, row, context) do
    existing =
      one(
        repo,
        "SELECT candidate_id,result_revision_id,approval_hash FROM acceptances WHERE approval_id=$1::uuid",
        [context.approval.id]
      )

    if existing do
      replay_candidate_acceptance(repo, existing, candidate_id, row, context)
    else
      accept_fresh_candidate(repo, candidate_id, screenplay, row, context)
    end
  end

  defp replay_candidate_acceptance(repo, existing, candidate_id, row, context) do
    if existing["candidate_id"] == candidate_id and
         existing["result_revision_id"] == row["result_revision_id"] and
         existing["approval_hash"] == context.approval_hash do
      context.model
    else
      rollback(repo, :approval_identity_conflict)
    end
  end

  defp accept_fresh_candidate(repo, candidate_id, screenplay, row, context) do
    cond do
      row["decision"] == "rejected" ->
        rollback(repo, :already_rejected)

      row["decision"] == "accepted" ->
        rollback(repo, :acceptance_identity_conflict)

      screenplay["head_revision_id"] != context.approval.base_revision_id ->
        rollback(repo, {:stale_revision, screenplay["head_revision_id"]})

      true ->
        record_candidate_acceptance(repo, candidate_id, row, context)
    end
  end

  defp record_candidate_acceptance(repo, candidate_id, row, context) do
    operations = Enum.flat_map(row["change_groups"] || [], &Map.get(&1, "operations", []))
    approval = context.approval
    review = approval.review
    approval_map = Approval.to_map(approval)
    review_map = Review.to_map(review)
    origin = accepted_origin(row["provenance"] || %{})

    q(
      repo,
      "INSERT INTO acceptances(id,screenplay_id,base_revision_id,result_revision_id,candidate_id,actor,origin,operations,provenance,review,acceptance_kind,approval_id,approval_hash,approval,approver_type,approver_id,reviewer_type,reviewer_id,review_hash,check_set_fingerprint,report_ids,run_id,run_policy_version,run_policy_fingerprint) VALUES($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::uuid,$6,$7,$8::jsonb,$9::jsonb,$10::jsonb,$11,$12::uuid,$13,$14::jsonb,$15,$16,$17,$18,$19,$20,$21::jsonb,$22::uuid,$23,$24)",
      [
        ID.v4(),
        context.model.id,
        approval.base_revision_id,
        context.model.revision.id,
        candidate_id,
        approval.approver.id,
        origin,
        json(operations),
        json(row["provenance"] || %{}),
        json(review_map),
        "approved",
        approval.id,
        context.approval_hash,
        json(approval_map),
        Atom.to_string(approval.approver.type),
        approval.approver.id,
        Atom.to_string(review.reviewer.type),
        review.reviewer.id,
        context.review_hash,
        row["check_set_fingerprint"],
        json(review.report_ids),
        approval.run_id,
        approval.run_policy_version,
        approval.run_policy_fingerprint
      ]
    )

    q(
      repo,
      "UPDATE writing_candidates SET decision='accepted',decision_actor=$2,decided_at=now(),review_hash=$3,approval_id=$4::uuid WHERE id=$1::uuid",
      [candidate_id, approval.approver.id, context.review_hash, approval.id]
    )

    set_head(repo, context.model.id, context.model.revision.id)
    context.model
  end

  defp accepted_origin(%{"origin" => origin})
       when origin in ["writer_edit", "imported_text", "generated_text", "generated_structural_edit", "mixed"],
       do: origin

  defp accepted_origin(_), do: "mixed"

  @doc "Rejects a candidate while preserving its material for history and recovery."
  def reject_candidate(repo, candidate_id, opts) when is_list(opts) do
    transaction(repo, fn -> reject_candidate_locked(repo, candidate_id, opts) end)
  end

  defp reject_candidate_locked(repo, candidate_id, opts) do
    row =
      one(repo, "SELECT * FROM writing_candidates WHERE id=$1::uuid FOR UPDATE", [candidate_id]) ||
        rollback(repo, :not_found)

    case row["decision"] do
      "accepted" ->
        rollback(repo, :already_accepted)

      "rejected" ->
        row

      _ ->
        actor = Keyword.get(opts, :actor)
        unless is_binary(actor) and String.trim(actor) != "", do: rollback(repo, :missing_actor)

        q(
          repo,
          "UPDATE writing_candidates SET decision='rejected',decision_actor=$2,decided_at=now() WHERE id=$1::uuid",
          [candidate_id, actor]
        )

        Map.put(row, "decision", "rejected")
    end
  end

  @doc "Stores a revision-scoped analysis report with checked source revisions."
  def save_report(repo, report, opts \\ []) when is_map(report) do
    primary_id = field(report, :primary_revision_id)

    context = %{
      id: field(report, :id) || ID.v4(),
      screenplay_id: field(report, :screenplay_id),
      primary_id: primary_id,
      source_ids: Enum.uniq([primary_id | field(report, :source_revision_ids) || []]),
      payload: field(report, :payload) || %{}
    }

    transaction(repo, fn -> persist_report(repo, report, opts, context) end)
  end

  defp persist_report(repo, report, opts, context) do
    Enum.each(Keyword.get(opts, :source_models, []), &save_report_source_model(repo, context.screenplay_id, &1))
    sources = Map.new(context.source_ids, &load_report_source(repo, context.screenplay_id, &1))
    evidence = field(context.payload, :evidence) || []
    registry = Enum.reduce(evidence, %{}, &validate_report_evidence(repo, context.screenplay_id, sources, &1, &2))
    citations = field(context.payload, :citations) || []
    if Enum.any?(citations, &(!Map.has_key?(registry, &1))), do: rollback(repo, :uninspected_citation)

    if !is_binary(field(report, :fingerprint)) or !is_binary(field(report, :tool)),
      do: rollback(repo, :invalid_report)

    insert_report(repo, report, context)
    Map.put(report, :id, context.id)
  end

  defp save_report_source_model(repo, screenplay_id, model) do
    if model.id != screenplay_id, do: rollback(repo, :wrong_screenplay)

    if !one(repo, "SELECT id FROM revisions WHERE screenplay_id=$1::uuid AND id=$2::uuid", [
         screenplay_id,
         model.revision.id
       ]),
       do: insert_revision(repo, Model.refresh(model))
  end

  defp load_report_source(repo, screenplay_id, source_id) do
    case load_revision(repo, screenplay_id, source_id) do
      {:ok, model} -> {source_id, model}
      _ -> rollback(repo, {:unknown_report_source, source_id})
    end
  end

  defp validate_report_evidence(repo, screenplay_id, sources, entry, registry) do
    evidence_id = field(entry, :evidence_id)
    revision_id = field(entry, :revision_id)
    target = field(entry, :target)
    excerpt = field(entry, :excerpt)
    source = sources[revision_id] || rollback(repo, :unlisted_evidence_revision)
    if !is_binary(evidence_id) or Map.has_key?(registry, evidence_id), do: rollback(repo, :invalid_evidence_id)
    if field(entry, :screenplay_id) != screenplay_id, do: rollback(repo, :foreign_evidence)

    value =
      case Fount.Target.resolve(source, target) do
        {:ok, item} -> item
        _ -> rollback(repo, :invalid_evidence_target)
      end

    verify_report_excerpt(repo, value, target, excerpt)
    Map.put(registry, evidence_id, entry)
  end

  defp verify_report_excerpt(repo, value, target, excerpt) do
    text = if is_map(value), do: Map.get(value, :text), else: nil
    span = field(target, :span)
    span = if is_map(span), do: {field(span, :byte_start), field(span, :byte_end)}, else: span
    valid = if span, do: UTF8Span.verify(text, span, excerpt) == :ok, else: text == excerpt
    if !valid, do: rollback(repo, :evidence_excerpt_mismatch)
  end

  defp insert_report(repo, report, context) do
    q(
      repo,
      "INSERT INTO analysis_reports(id,screenplay_id,primary_revision_id,session_id,tool,status,fingerprint,payload) VALUES($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5,$6,$7,$8::jsonb)",
      [
        context.id,
        context.screenplay_id,
        context.primary_id,
        field(report, :session_id),
        field(report, :tool),
        field(report, :status) || "complete",
        field(report, :fingerprint),
        json(context.payload)
      ]
    )

    Enum.each(context.source_ids, fn source_id ->
      q(
        repo,
        "INSERT INTO analysis_report_sources(screenplay_id,report_id,revision_id) VALUES($1::uuid,$2::uuid,$3::uuid)",
        [context.screenplay_id, context.id, source_id]
      )
    end)
  end

  def report(repo, id) do
    case one(repo, "SELECT * FROM analysis_reports WHERE id=$1::uuid", [id]) do
      nil -> {:error, :not_found}
      row -> {:ok, row}
    end
  end

  def history_page(repo, screenplay_id, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    limit = min(max(Keyword.get(opts, :limit, 50), 1), 499)
    rows = history(repo, screenplay_id, limit: limit + 1, head: cursor)
    {items, rest} = Enum.split(rows, limit)

    %{
      items: items,
      next_cursor:
        case rest do
          [next | _] -> next.id
          [] -> nil
        end
    }
  end

  defp candidate_payload(candidate) do
    Map.new([:parent_candidate_id, :label, :strategy, :change_groups, :lineage, :provenance], fn key ->
      default =
        case key do
          :label -> "Candidate"
          :change_groups -> []
          :lineage -> []
          :parent_candidate_id -> nil
          _ -> %{}
        end

      {to_string(key), field(candidate, key) || default}
    end)
    |> Model.plain()
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, to_string(key)))

  defp insert_revision(repo, model) do
    case one(repo, "SELECT screenplay_id,content_hash,render_hash,model FROM revisions WHERE id=$1::uuid", [
           model.revision.id
         ]) do
      nil ->
        insert_new_revision(repo, model)

      row ->
        if row["screenplay_id"] != model.id or row["content_hash"] != model.revision.content_hash or
             row["render_hash"] != model.revision.render_hash or row["model"] != Codec.encode(model),
           do: rollback(repo, :revision_identity_conflict)

        :ok
    end
  end

  defp insert_new_revision(repo, model) do
    artifact_id = insert_artifact(repo, model)
    revision = model.revision

    q(
      repo,
      "INSERT INTO revisions(id,screenplay_id,parent_id,artifact_id,content_hash,render_hash,model,actor,message,inserted_at) VALUES($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5,$6,$7::jsonb,$8,$9,$10::timestamptz)",
      [
        revision.id,
        model.id,
        revision.parent_id,
        artifact_id,
        revision.content_hash,
        revision.render_hash,
        json(Codec.encode(model)),
        revision.actor,
        revision.message,
        revision.created_at || DateTime.utc_now()
      ]
    )

    insert_projection(repo, model)
  end

  defp insert_artifact(_repo, %{import: nil}), do: nil

  defp insert_artifact(repo, model) do
    import = model.import
    id = import[:id] || ID.v5(model.id, ["artifact:", ID.hash(import.bytes)])

    q(
      repo,
      "INSERT INTO import_artifacts(id,screenplay_id,format,original_bytes,bytes_sha256,render_hash,fidelity) VALUES($1::uuid,$2::uuid,$3,$4::bytea,$5,$6,$7::jsonb) ON CONFLICT(id) DO NOTHING",
      [
        id,
        model.id,
        to_string(import.format),
        import.bytes,
        ID.hash(import.bytes),
        import.render_hash || model.revision.render_hash,
        json(%{"losses" => import[:losses] || []})
      ]
    )

    id
  end

  defp insert_projection(repo, model) do
    sid = model.id
    rid = model.revision.id
    scene_for = Map.new(for scene <- model.ir.scenes, element_id <- scene.element_ids, do: {element_id, scene.id})

    block_for =
      Map.new(
        for block <- model.ir.dialogue_blocks, element_id <- [block.cue_id | block.body_ids], do: {element_id, block.id}
      )

    insert_projection_titles_scenes(repo, model, sid, rid)
    insert_projection_script(repo, model, sid, rid, scene_for, block_for)
    insert_projection_cast(repo, model, sid, rid)
  end

  defp insert_projection_titles_scenes(repo, model, sid, rid) do
    Enum.with_index((model.ir.title_page && model.ir.title_page.entries) || [])
    |> Enum.each(fn {entry, ordinal} ->
      q(
        repo,
        "INSERT INTO title_entries(screenplay_id,revision_id,id,ordinal,key,values) VALUES($1::uuid,$2::uuid,$3::uuid,$4,$5,$6::text[])",
        [sid, rid, entry.id, ordinal, entry.key, entry.values]
      )
    end)

    Enum.with_index(model.ir.scenes)
    |> Enum.each(fn {scene, ordinal} ->
      q(
        repo,
        "INSERT INTO scenes(screenplay_id,revision_id,id,ordinal,heading_element_id,scene_number,omitted) VALUES($1::uuid,$2::uuid,$3::uuid,$4,$5::uuid,$6,$7)",
        [sid, rid, scene.id, ordinal, scene.heading_id, scene.number, scene.omitted?]
      )
    end)
  end

  defp insert_projection_script(repo, model, sid, rid, scene_for, block_for) do
    Enum.with_index(model.ir.dialogue_blocks)
    |> Enum.each(fn {block, ordinal} ->
      q(
        repo,
        "INSERT INTO dialogue_blocks(screenplay_id,revision_id,id,ordinal,scene_id,cue_element_id,dual_with_id,side) VALUES($1::uuid,$2::uuid,$3::uuid,$4,$5::uuid,$6::uuid,$7::uuid,$8)",
        [
          sid,
          rid,
          block.id,
          ordinal,
          scene_for[block.cue_id],
          block.cue_id,
          block.dual_with,
          block.side && to_string(block.side)
        ]
      )
    end)

    Enum.with_index(model.ir.elements)
    |> Enum.each(fn {element, ordinal} ->
      q(
        repo,
        "INSERT INTO elements(screenplay_id,revision_id,id,ordinal,scene_id,dialogue_block_id,type,text,raw_text,inline,attrs,source_reference,origin) VALUES($1::uuid,$2::uuid,$3::uuid,$4,$5::uuid,$6::uuid,$7,$8,$9,$10::jsonb,$11::jsonb,$12::jsonb,$13)",
        [
          sid,
          rid,
          element.id,
          ordinal,
          scene_for[element.id],
          block_for[element.id],
          to_string(element.type),
          element.text,
          element.raw_text,
          json(Model.plain(element.inline || [])),
          json(Model.plain(element.attrs || %{})),
          element.source_span && json(Model.plain(element.source_span)),
          element.origin && to_string(element.origin)
        ]
      )
    end)
  end

  defp insert_projection_cast(repo, model, sid, rid) do
    Enum.each(model.cast, fn {_id, character} ->
      q(
        repo,
        "INSERT INTO characters(screenplay_id,revision_id,id,display_name,notes,attributes) VALUES($1::uuid,$2::uuid,$3::uuid,$4,$5,$6::jsonb)",
        [
          sid,
          rid,
          character.id,
          character.display_name,
          character.notes,
          json(Model.plain(character.attributes || %{}))
        ]
      )

      Enum.each(character.aliases || [], fn alias_entry ->
        surface = alias_entry[:alias] || alias_entry["alias"]
        kind = alias_entry[:kind] || alias_entry["kind"] || :name

        q(
          repo,
          "INSERT INTO character_aliases(screenplay_id,revision_id,character_id,alias,normalized_alias,kind) VALUES($1::uuid,$2::uuid,$3::uuid,$4,$5,$6)",
          [sid, rid, character.id, surface, String.downcase(surface), to_string(kind)]
        )
      end)
    end)

    Enum.each(model.mentions, fn {_id, mention} ->
      q(
        repo,
        "INSERT INTO mentions(screenplay_id,revision_id,id,element_id,character_id,role,status,surface,byte_start,byte_end,producer,confidence) VALUES($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::uuid,$6,$7,$8,$9,$10,$11,$12)",
        [
          sid,
          rid,
          mention.id,
          mention.element_id,
          mention.character_id,
          to_string(mention.role),
          to_string(mention.status),
          mention.surface,
          mention.byte_start,
          mention.byte_end,
          mention.producer || "writer",
          mention.confidence
        ]
      )
    end)

    Enum.each(model.authored_items, fn {_id, item} ->
      q(
        repo,
        "INSERT INTO authored_items(screenplay_id,revision_id,id,namespace,kind,target,value,dependencies,status,provenance) VALUES($1::uuid,$2::uuid,$3::uuid,$4,$5,$6::jsonb,$7::jsonb,$8::jsonb,$9,$10::jsonb)",
        [
          sid,
          rid,
          item["id"],
          item["namespace"],
          item["kind"],
          json(item["target"]),
          json(item["value"]),
          json(item["dependencies"] || []),
          item["status"],
          json(item["provenance"] || %{})
        ]
      )
    end)
  end

  defp acceptance_details(opts) do
    %{
      actor: Keyword.get(opts, :actor, "writer"),
      origin: Keyword.get(opts, :origin, :writer_edit),
      operations: Keyword.get(opts, :operations, []),
      provenance: Keyword.get(opts, :provenance, %{}),
      review: Keyword.get(opts, :review, %{}),
      candidate_id: nil
    }
  end

  defp acceptance(repo, model, parent, details) do
    q(
      repo,
      "INSERT INTO acceptances(id,screenplay_id,base_revision_id,result_revision_id,candidate_id,actor,origin,operations,provenance,review,acceptance_kind) VALUES($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::uuid,$6,$7,$8::jsonb,$9::jsonb,$10::jsonb,$11)",
      [
        ID.v4(),
        model.id,
        parent,
        model.revision.id,
        details.candidate_id,
        details.actor,
        to_string(details.origin),
        json(details.operations),
        json(details.provenance),
        json(details.review),
        "genesis"
      ]
    )
  end

  defp set_head(repo, id, revision),
    do: q(repo, "UPDATE screenplays SET head_revision_id=$2::uuid,updated_at=now() WHERE id=$1::uuid", [id, revision])

  defp validate(model), do: if(Fount.Validate.screenplay(model) == [], do: :ok, else: {:error, :invalid_model})
  defp json(value), do: Jason.encode!(value)
  defp uuid?(value), do: is_binary(value) and Regex.match?(~r/^[0-9a-f-]{36}$/, value)

  defp q(repo, sql, params),
    do:
      SQL.query!(
        repo,
        sql |> String.replace("::uuid", "::text::uuid") |> String.replace("::jsonb", "::text::jsonb"),
        params,
        log: false
      )

  defp one(repo, sql, params), do: List.first(all(repo, sql, params))

  defp all(repo, sql, params) do
    result = q(repo, sql, params)

    Enum.map(result.rows, fn row ->
      result.columns
      |> Enum.zip(row)
      |> Map.new(fn
        {column, <<_::binary-size(16)>> = value}
        when column in [
               "id",
               "head_revision_id",
               "parent_id",
               "screenplay_id",
               "artifact_id",
               "base_revision_id",
               "result_revision_id",
               "parent_candidate_id",
               "primary_revision_id",
               "revision_id",
               "session_id",
               "candidate_id",
               "approval_id",
               "run_id"
             ] ->
          {:ok, id} = Ecto.UUID.load(value)
          {column, id}

        pair ->
          pair
      end)
    end)
  end

  defp guarded_write(repo, opts, kind, identity) do
    case Keyword.get(opts, :guard) do
      nil ->
        :ok

      guard when is_function(guard, 2) ->
        case guard.(kind, identity) do
          :ok -> :ok
          {:error, reason} -> rollback(repo, reason)
          _ -> rollback(repo, :invalid_write_guard_result)
        end

      _ ->
        rollback(repo, :invalid_write_guard)
    end
  end

  defp rollback(repo, reason), do: repo.rollback(reason)
  defp transaction(repo, fun), do: repo.transaction(fun)
end
