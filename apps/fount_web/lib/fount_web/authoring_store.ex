defmodule FountWeb.AuthoringStore do
  @moduledoc "Owner-scoped recovery storage for raw working drafts. It never owns canonical screenplay state."

  alias Ecto.Adapters.SQL

  @uuid_columns ~w(id project_id screenplay_id base_revision_id saved_candidate_id draft_id)
  @default_history_limit 30
  @default_draft_limit 12
  @default_max_source_bytes 1_048_576

  def limits do
    config = Application.get_env(:fount_web, :authoring, [])

    %{
      history: Keyword.get(config, :history_limit, @default_history_limit),
      drafts: Keyword.get(config, :draft_limit, @default_draft_limit),
      max_source_bytes: Keyword.get(config, :max_source_bytes, @default_max_source_bytes)
    }
  end

  def open(repo, owner, project, base, opts \\ [])
      when is_binary(owner) and is_map(project) and is_struct(base, Fount.Screenplay) do
    raw = Keyword.get(opts, :source, Fount.Screenplay.to_fountain(base))

    with :ok <- validate_source(raw) do
      transaction(repo, fn ->
        case latest_active_for_update(repo, owner, project["id"]) do
          nil -> create_locked(repo, owner, project, base, raw)
          draft -> draft
        end
      end)
    end
  end

  def get(repo, owner, draft_id) when is_binary(owner) and is_binary(draft_id) do
    case query(
           repo,
           "SELECT * FROM fount_web_drafts WHERE owner_id=$1 AND id=$2::text::uuid",
           [owner, draft_id]
         ) do
      [row] -> {:ok, row}
      [] -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def save(repo, owner, draft_id, expected_version, raw, attrs \\ %{})
      when is_binary(owner) and is_binary(draft_id) and is_integer(expected_version) and is_binary(raw) and
             is_map(attrs) do
    with :ok <- validate_source(raw) do
      transaction(repo, fn ->
        draft = lock_owned!(repo, owner, draft_id)
        ensure_active!(repo, draft)
        hash = Fount.ID.hash(raw)

        cond do
          draft["version"] == expected_version ->
            snapshot_locked(repo, draft, Map.get(attrs, :reason, Map.get(attrs, "reason", "autosave")))
            update_locked(repo, draft, raw, hash, attrs)

          draft["version"] == expected_version + 1 and draft["source_sha256"] == hash ->
            Map.put(draft, "save_replay", true)

          true ->
            rollback(repo, {:stale_draft, public_conflict(draft)})
        end
      end)
    end
  end

  def rebase(repo, owner, draft_id, expected_version, base_revision_id)
      when is_binary(owner) and is_binary(draft_id) and is_integer(expected_version) and
             is_binary(base_revision_id) do
    transaction(repo, fn ->
      draft = lock_owned!(repo, owner, draft_id)
      ensure_active!(repo, draft)
      ensure_version!(repo, draft, expected_version)
      ensure_revision!(repo, draft["screenplay_id"], base_revision_id)
      snapshot_locked(repo, draft, "rebase")

      result =
        q!(
          repo,
          "UPDATE fount_web_drafts SET base_revision_id=$3::text::uuid,version=version+1,saved_candidate_id=NULL,saved_candidate_version=NULL,updated_at=now() WHERE owner_id=$1 AND id=$2::text::uuid RETURNING *",
          [owner, draft_id, base_revision_id]
        )

      one(result)
    end)
  end

  def bind_candidate(repo, owner, draft_id, expected_version, candidate_id)
      when is_binary(owner) and is_binary(draft_id) and is_integer(expected_version) and is_binary(candidate_id) do
    transaction(repo, fn ->
      draft = lock_owned!(repo, owner, draft_id)
      ensure_active!(repo, draft)
      ensure_version!(repo, draft, expected_version)

      result =
        q!(
          repo,
          "UPDATE fount_web_drafts SET saved_candidate_id=$4::text::uuid,saved_candidate_version=$3,updated_at=now() WHERE owner_id=$1 AND id=$2::text::uuid RETURNING *",
          [owner, draft_id, expected_version, candidate_id]
        )

      one(result)
    end)
  end

  def mark_accepted(repo, owner, draft_id, candidate_id)
      when is_binary(owner) and is_binary(draft_id) and is_binary(candidate_id) do
    case SQL.query(
           repo,
           "UPDATE fount_web_drafts SET status='accepted',updated_at=now() WHERE owner_id=$1 AND id=$2::text::uuid AND saved_candidate_id=$3::text::uuid AND status='active' RETURNING *",
           [owner, draft_id, candidate_id],
           log: false
         ) do
      {:ok, %{num_rows: 1} = result} -> {:ok, one(result)}
      {:ok, _} -> {:error, :candidate_not_bound}
      {:error, _} -> {:error, :storage_error}
    end
  end

  def discard(repo, owner, draft_id, expected_version)
      when is_binary(owner) and is_binary(draft_id) and is_integer(expected_version) do
    transaction(repo, fn ->
      draft = lock_owned!(repo, owner, draft_id)
      ensure_active!(repo, draft)
      ensure_version!(repo, draft, expected_version)
      snapshot_locked(repo, draft, "discard")

      result =
        q!(
          repo,
          "UPDATE fount_web_drafts SET status='discarded',version=version+1,updated_at=now() WHERE owner_id=$1 AND id=$2::text::uuid RETURNING *",
          [owner, draft_id]
        )

      one(result)
    end)
  end

  def history(repo, owner, draft_id, limit \\ @default_history_limit)
      when is_binary(owner) and is_binary(draft_id) and is_integer(limit) do
    limit = limit |> max(1) |> min(limits().history)

    query(
      repo,
      "SELECT h.* FROM fount_web_draft_history h JOIN fount_web_drafts d ON d.id=h.draft_id WHERE h.owner_id=$1 AND h.draft_id=$2::text::uuid AND d.owner_id=$1 ORDER BY h.inserted_at DESC,h.id DESC LIMIT $3",
      [owner, draft_id, limit]
    )
  end

  @doc "Forks conflicting client text into a new recovery draft bound to the same base revision."
  def fork(repo, owner, draft_id, raw)
      when is_binary(owner) and is_binary(draft_id) and is_binary(raw) do
    with :ok <- validate_source(raw) do
      transaction(repo, fn ->
        source = lock_owned!(repo, owner, draft_id)
        ensure_active!(repo, source)

        project =
          one_row(repo, "SELECT * FROM fount_web_projects WHERE owner_id=$1 AND id=$2::text::uuid", [
            owner,
            source["project_id"]
          ]) || rollback(repo, :project_not_found)

        base =
          case Fount.Persistence.load_revision(repo, source["screenplay_id"], source["base_revision_id"]) do
            {:ok, model} -> model
            {:error, _} -> rollback(repo, :base_revision_not_found)
          end

        create_locked(repo, owner, project, base, raw)
      end)
    end
  end

  def restore(repo, owner, draft_id, history_id)
      when is_binary(owner) and is_binary(draft_id) and is_binary(history_id) do
    transaction(repo, fn ->
      source =
        one_row(
          repo,
          "SELECT h.* FROM fount_web_draft_history h JOIN fount_web_drafts d ON d.id=h.draft_id WHERE h.owner_id=$1 AND h.draft_id=$2::text::uuid AND h.id=$3::text::uuid AND d.owner_id=$1 FOR SHARE OF d",
          [owner, draft_id, history_id]
        ) || rollback(repo, :history_not_found)

      project =
        one_row(repo, "SELECT * FROM fount_web_projects WHERE owner_id=$1 AND id=$2::text::uuid", [
          owner,
          source["project_id"]
        ]) || rollback(repo, :project_not_found)

      base =
        case Fount.Persistence.load_revision(repo, source["screenplay_id"], source["base_revision_id"]) do
          {:ok, model} -> model
          {:error, _} -> rollback(repo, :base_revision_not_found)
        end

      create_locked(repo, owner, project, base, source["raw_source"])
    end)
  end

  defp create_locked(repo, owner, project, base, raw) do
    enforce_draft_limit!(repo, owner, project["id"])
    id = Fount.ID.v4()
    hash = Fount.ID.hash(raw)

    result =
      q!(
        repo,
        "INSERT INTO fount_web_drafts(id,project_id,owner_id,screenplay_id,base_revision_id,raw_source,source_sha256,last_valid_source,last_valid_sha256,last_valid_fidelity,identity_anchors,version,status,inserted_at,updated_at) VALUES($1::text::uuid,$2::text::uuid,$3,$4::text::uuid,$5::text::uuid,$6,$7,$6,$7,'{}'::jsonb,$8::jsonb,1,'active',now(),now()) RETURNING *",
        [id, project["id"], owner, base.id, base.revision.id, raw, hash, Jason.encode!(Fount.Identity.anchors(base.ir))]
      )

    one(result)
  end

  defp update_locked(repo, draft, raw, hash, attrs) do
    valid? = Map.get(attrs, :valid?, Map.get(attrs, "valid?", false))
    fidelity = Map.get(attrs, :fidelity, Map.get(attrs, "fidelity", %{}))
    identity_anchors = Map.get(attrs, :identity_anchors, Map.get(attrs, "identity_anchors", []))
    next_version = draft["version"] + 1

    {last_valid_source, last_valid_sha, last_valid_fidelity, next_identity_anchors} =
      if valid? do
        {raw, hash, fidelity, identity_anchors}
      else
        {
          draft["last_valid_source"],
          draft["last_valid_sha256"],
          draft["last_valid_fidelity"] || %{},
          draft["identity_anchors"] || []
        }
      end

    result =
      q!(
        repo,
        "UPDATE fount_web_drafts SET raw_source=$3,source_sha256=$4,last_valid_source=$5,last_valid_sha256=$6,last_valid_fidelity=$7::jsonb,identity_anchors=$8::jsonb,version=$9,saved_candidate_id=NULL,saved_candidate_version=NULL,updated_at=now() WHERE owner_id=$1 AND id=$2::text::uuid RETURNING *",
        [
          draft["owner_id"],
          draft["id"],
          raw,
          hash,
          last_valid_source,
          last_valid_sha,
          Jason.encode!(last_valid_fidelity),
          Jason.encode!(next_identity_anchors),
          next_version
        ]
      )

    prune_history!(repo, draft["id"])
    one(result)
  end

  defp snapshot_locked(repo, draft, reason) do
    q!(
      repo,
      "INSERT INTO fount_web_draft_history(id,draft_id,project_id,owner_id,screenplay_id,base_revision_id,draft_version,raw_source,source_sha256,reason,inserted_at) VALUES($1::text::uuid,$2::text::uuid,$3::text::uuid,$4,$5::text::uuid,$6::text::uuid,$7,$8,$9,$10,now()) ON CONFLICT(draft_id,draft_version) DO NOTHING",
      [
        Fount.ID.v4(),
        draft["id"],
        draft["project_id"],
        draft["owner_id"],
        draft["screenplay_id"],
        draft["base_revision_id"],
        draft["version"],
        draft["raw_source"],
        draft["source_sha256"],
        to_string(reason || "save")
      ]
    )
  end

  defp prune_history!(repo, draft_id) do
    limit = limits().history

    q!(
      repo,
      "DELETE FROM fount_web_draft_history WHERE id IN (SELECT id FROM fount_web_draft_history WHERE draft_id=$1::text::uuid ORDER BY inserted_at DESC,id DESC OFFSET $2)",
      [draft_id, limit]
    )
  end

  defp enforce_draft_limit!(repo, owner, project_id) do
    limit = limits().drafts

    count =
      one_row(
        repo,
        "SELECT count(*)::bigint AS count FROM fount_web_drafts WHERE owner_id=$1 AND project_id=$2::text::uuid AND status='active'",
        [owner, project_id]
      )["count"]

    if count >= limit, do: rollback(repo, :draft_limit_reached)
  end

  defp latest_active_for_update(repo, owner, project_id) do
    one_row(
      repo,
      "SELECT * FROM fount_web_drafts WHERE owner_id=$1 AND project_id=$2::text::uuid AND status='active' ORDER BY updated_at DESC,id DESC LIMIT 1 FOR UPDATE",
      [owner, project_id]
    )
  end

  defp lock_owned!(repo, owner, draft_id) do
    one_row(
      repo,
      "SELECT * FROM fount_web_drafts WHERE owner_id=$1 AND id=$2::text::uuid FOR UPDATE",
      [owner, draft_id]
    ) || rollback(repo, :not_found)
  end

  defp ensure_active!(repo, draft) do
    if draft["status"] != "active", do: rollback(repo, :draft_not_active)
  end

  defp ensure_version!(repo, draft, expected) do
    if draft["version"] != expected,
      do: rollback(repo, {:stale_draft, public_conflict(draft)})
  end

  defp ensure_revision!(repo, screenplay_id, revision_id) do
    unless one_row(
             repo,
             "SELECT id::text FROM revisions WHERE screenplay_id=$1::text::uuid AND id=$2::text::uuid",
             [screenplay_id, revision_id]
           ),
      do: rollback(repo, :base_revision_not_found)
  end

  defp validate_source(raw) do
    max = limits().max_source_bytes
    if byte_size(raw) <= max, do: :ok, else: {:error, {:source_too_large, max}}
  end

  defp public_conflict(draft) do
    Map.take(draft, [
      "id",
      "version",
      "base_revision_id",
      "source_sha256",
      "raw_source",
      "updated_at",
      "saved_candidate_id",
      "saved_candidate_version"
    ])
  end

  defp transaction(repo, fun) do
    case repo.transaction(fun) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :storage_error}
  end

  defp rollback(repo, reason), do: repo.rollback(reason)

  defp query(repo, statement, params) do
    case SQL.query(repo, statement, params, log: false) do
      {:ok, result} -> rows(result)
      {:error, _} -> {:error, :storage_error}
    end
  end

  defp one_row(repo, statement, params) do
    case SQL.query(repo, statement, params, log: false) do
      {:ok, result} -> one(result)
      {:error, _} -> nil
    end
  end

  defp q!(repo, statement, params), do: SQL.query!(repo, statement, params, log: false)
  defp one(%{rows: []}), do: nil
  defp one(result), do: result |> rows() |> List.first()
  defp rows(%{columns: columns, rows: rows}), do: Enum.map(rows, &row_map(columns, &1))
  defp row_map(columns, row), do: Map.new(Enum.zip(columns, row), &decode_column/1)

  defp decode_column({column, <<_::binary-size(16)>> = value}) when column in @uuid_columns do
    {:ok, uuid} = Ecto.UUID.load(value)
    {column, uuid}
  end

  defp decode_column(pair), do: pair
end
