defmodule Fount.Persistence do
  @moduledoc "Immutable PostgreSQL revisions and explicit writer decisions for screenplays."

  alias Fount.{ID, Screenplay}
  alias Fount.Persistence.Codec
  alias Fount.Screenplay.Model

  def migrations_path, do: Application.app_dir(:fount, "priv/repo/migrations")

  def create(repo, key, %Screenplay{} = root, opts \\ []) do
    root = Model.refresh(root)

    with :ok <- validate(root),
         true <- is_nil(root.revision.parent_id) do
      transaction(repo, fn ->
        if one(repo, "SELECT id FROM screenplays WHERE key=$1", [key]), do: rollback(repo, :key_taken)
        q(repo, "INSERT INTO screenplays(id,key) VALUES($1::uuid,$2)", [root.id, key])
        insert_revision(repo, root)

        acceptance(
          repo,
          root,
          nil,
          Keyword.get(opts, :actor, "writer"),
          Keyword.get(opts, :origin, :writer_edit),
          Keyword.get(opts, :operations, []),
          Keyword.get(opts, :provenance, %{}),
          Keyword.get(opts, :review, %{})
        )

        set_head(repo, root.id, root.revision.id)
        root
      end)
    else
      false -> {:error, :root_has_parent}
      error -> error
    end
  end

  def save(repo, key, %Screenplay{} = model, opts \\ []),
    do: save_edit(repo, key, model, opts)

  def save_edit(repo, key, %Screenplay{} = candidate, opts \\ []) do
    candidate = Model.refresh(candidate)

    with :ok <- validate(candidate) do
      transaction(repo, fn ->
        row =
          one(repo, "SELECT id,head_revision_id FROM screenplays WHERE key=$1 FOR UPDATE", [key]) ||
            rollback(repo, :not_found)

        if row["id"] != candidate.id, do: rollback(repo, :wrong_screenplay)
        actual = row["head_revision_id"]

        expected =
          Keyword.get(
            opts,
            :expected_revision,
            if(candidate.revision.id == actual, do: actual, else: candidate.revision.parent_id)
          )

        if actual != expected, do: rollback(repo, {:stale_revision, actual})
        if candidate.revision.id != actual and candidate.revision.parent_id != actual, do: rollback(repo, :wrong_parent)

        if candidate.revision.id == actual do
          # A repeated save is a no-op only for the exact persisted identity.
          insert_revision(repo, candidate)
          candidate
        else
          insert_revision(repo, candidate)

          acceptance(
            repo,
            candidate,
            actual,
            Keyword.get(opts, :actor, "writer"),
            Keyword.get(opts, :origin, :writer_edit),
            Keyword.get(opts, :operations, []),
            Keyword.get(opts, :provenance, %{}),
            Keyword.get(opts, :review, %{})
          )

          set_head(repo, candidate.id, candidate.revision.id)
          candidate
        end
      end)
    end
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
  def save_session(repo, session) when is_map(session) do
    id = field(session, :id) || ID.v4()
    screenplay_id = field(session, :screenplay_id)
    base_id = field(session, :base_revision_id)

    transaction(repo, fn ->
      previous = one(repo, "SELECT * FROM writing_sessions WHERE id=$1::uuid FOR UPDATE", [id])

      if previous do
        if previous["screenplay_id"] != screenplay_id or previous["base_revision_id"] != base_id or
             previous["request"] != field(session, :request),
           do: rollback(repo, :immutable_session_fields)

        if previous["lock_version"] != field(session, :lock_version), do: rollback(repo, :stale_session)
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

        session |> Map.drop(["id", "lock_version"]) |> Map.put(:lock_version, next) |> Map.put(:id, id)
      else
        if !one(repo, "SELECT id FROM revisions WHERE screenplay_id=$1::uuid AND id=$2::uuid", [screenplay_id, base_id]),
           do: rollback(repo, :unknown_base)

        q(
          repo,
          "INSERT INTO writing_sessions(id,screenplay_id,base_revision_id,workflow,status,request,strategies,progress,provenance) VALUES($1::uuid,$2::uuid,$3::uuid,$4,$5,$6::jsonb,$7::jsonb,$8::jsonb,$9::jsonb)",
          [
            id,
            screenplay_id,
            base_id,
            field(session, :workflow),
            field(session, :status) || "open",
            json(field(session, :request) || %{}),
            json(field(session, :strategies) || []),
            json(field(session, :progress) || %{}),
            json(field(session, :provenance) || %{})
          ]
        )

        session |> Map.drop(["id", "lock_version"]) |> Map.put(:id, id) |> Map.put(:lock_version, 1)
      end
    end)
  end

  @doc "Saves an immutable candidate revision without changing the accepted head."
  def save_candidate(repo, session_id, candidate) when is_map(candidate) do
    model = field(candidate, :screenplay) |> Model.refresh()

    with :ok <- validate(model) do
      transaction(repo, fn ->
        session =
          one(repo, "SELECT * FROM writing_sessions WHERE id=$1::uuid FOR SHARE", [session_id]) ||
            rollback(repo, :unknown_session)

        if session["screenplay_id"] != model.id or session["base_revision_id"] != model.revision.parent_id,
          do: rollback(repo, :wrong_base)

        id = field(candidate, :id) || ID.v4()
        previous = one(repo, "SELECT * FROM writing_candidates WHERE id=$1::uuid", [id])

        if previous do
          existing = one(repo, "SELECT content_hash FROM revisions WHERE id=$1::uuid", [previous["result_revision_id"]])

          if previous["result_revision_id"] != model.revision.id or
               existing["content_hash"] != model.revision.content_hash or
               candidate_payload(previous) != candidate_payload(candidate),
             do: rollback(repo, :candidate_identity_conflict)

          Map.put(candidate, :id, id)
        else
          insert_revision(repo, model)

          q(
            repo,
            "INSERT INTO writing_candidates(id,screenplay_id,session_id,base_revision_id,result_revision_id,parent_candidate_id,label,strategy,change_groups,lineage,provenance) VALUES($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::uuid,$6::uuid,$7,$8::jsonb,$9::jsonb,$10::jsonb,$11::jsonb)",
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
              json(field(candidate, :provenance) || %{})
            ]
          )

          q(repo, "UPDATE writing_candidates SET payload_hash=$2 WHERE id=$1::uuid", [
            id,
            Fount.Writing.CanonicalJSON.hash(candidate_payload(candidate))
          ])

          Map.put(candidate, :id, id)
        end
      end)
    end
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

  @doc "Accepts one reviewed candidate atomically when its base remains the head."

  def accept_candidate(repo, candidate_id, opts) when is_list(opts) do
    transaction(repo, fn ->
      identity =
        one(repo, "SELECT screenplay_id FROM writing_candidates WHERE id=$1::uuid", [candidate_id]) ||
          rollback(repo, :not_found)

      # All acceptances take the screenplay lock first, then the candidate lock.
      screenplay =
        one(repo, "SELECT head_revision_id FROM screenplays WHERE id=$1::uuid FOR UPDATE", [identity["screenplay_id"]])

      row =
        one(
          repo,
          "SELECT c.*,r.content_hash FROM writing_candidates c JOIN revisions r ON r.screenplay_id=c.screenplay_id AND r.id=c.result_revision_id WHERE c.id=$1::uuid FOR UPDATE OF c",
          [candidate_id]
        )

      expected = Keyword.get(opts, :expected_revision)
      review = Keyword.get(opts, :review)
      actor = Keyword.get(opts, :actor)
      unless is_map(review) and is_binary(actor) and String.trim(actor) != "", do: rollback(repo, :missing_review)
      unless field(review, :actor) == actor, do: rollback(repo, :review_actor_mismatch)
      review = Model.plain(review)
      review_hash = Fount.Writing.CanonicalJSON.hash(review)
      {:ok, model} = load_revision(repo, row["screenplay_id"], row["result_revision_id"])

      stored = %{
        "id" => candidate_id,
        "base_revision_id" => row["base_revision_id"],
        "content_hash" => row["content_hash"],
        "structural_errors" => Fount.Validate.screenplay(model),
        "checks" => row["provenance"]["checks"] || [],
        "report_ids" => row["provenance"]["report_ids"] || []
      }

      case Fount.Writing.ReviewGate.validate(stored, review, expected) do
        :ok -> :ok
        {:error, reason} -> rollback(repo, reason)
      end

      session =
        one(repo, "SELECT workflow,request FROM writing_sessions WHERE id=$1::uuid AND screenplay_id=$2::uuid", [
          row["session_id"],
          model.id
        ]) || rollback(repo, :candidate_session_mismatch)

      historical_source =
        if session["workflow"] == "recover",
          do: get_in(session["request"], ["options", "source_revision_id"]),
          else: nil

      historical_source =
        if is_binary(historical_source) and
             one(repo, "SELECT id FROM revisions WHERE screenplay_id=$1::uuid AND id=$2::uuid", [
               model.id,
               historical_source
             ]),
           do: [historical_source],
           else: []

      permitted_sources =
        [row["base_revision_id"], row["result_revision_id"] | historical_source]
        |> MapSet.new()

      Enum.each(stored["report_ids"], fn id ->
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
                 MapSet.member?(permitted_sources, report["primary_revision_id"]) and
                 Enum.all?(sources, &MapSet.member?(permitted_sources, &1["revision_id"])),
               do: rollback(repo, :report_lineage_mismatch)
      end)

      cond do
        row["decision"] == "rejected" ->
          rollback(repo, :already_rejected)

        row["decision"] == "accepted" and row["review_hash"] == review_hash and row["decision_actor"] == actor ->
          model

        row["decision"] == "accepted" ->
          rollback(repo, :acceptance_identity_conflict)

        screenplay["head_revision_id"] != expected ->
          rollback(repo, {:stale_revision, screenplay["head_revision_id"]})

        true ->
          operations = Enum.flat_map(row["change_groups"], & &1["operations"])
          acceptance(repo, model, expected, actor, :mixed, operations, row["provenance"], review, candidate_id)

          q(
            repo,
            "UPDATE writing_candidates SET decision='accepted',decision_actor=$2,decided_at=now(),review_hash=$3 WHERE id=$1::uuid",
            [candidate_id, actor, review_hash]
          )

          set_head(repo, model.id, model.revision.id)
          model
      end
    end)
  end

  @doc "Rejects a candidate while preserving its material for history and recovery."
  def reject_candidate(repo, candidate_id, opts) when is_list(opts) do
    transaction(repo, fn ->
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
    end)
  end

  @doc "Stores a revision-scoped analysis report with checked source revisions."
  def save_report(repo, report, opts \\ []) when is_map(report) do
    id = field(report, :id) || ID.v4()
    screenplay_id = field(report, :screenplay_id)
    primary_id = field(report, :primary_revision_id)
    source_ids = Enum.uniq([primary_id | field(report, :source_revision_ids) || []])
    payload = field(report, :payload) || %{}

    transaction(repo, fn ->
      Enum.each(Keyword.get(opts, :source_models, []), fn model ->
        if model.id != screenplay_id, do: rollback(repo, :wrong_screenplay)

        if !one(repo, "SELECT id FROM revisions WHERE screenplay_id=$1::uuid AND id=$2::uuid", [
             screenplay_id,
             model.revision.id
           ]),
           do: insert_revision(repo, Model.refresh(model))
      end)

      sources =
        Map.new(source_ids, fn source_id ->
          case load_revision(repo, screenplay_id, source_id) do
            {:ok, model} -> {source_id, model}
            _ -> rollback(repo, {:unknown_report_source, source_id})
          end
        end)

      evidence = field(payload, :evidence) || []

      registry =
        Enum.reduce(evidence, %{}, fn entry, acc ->
          evidence_id = field(entry, :evidence_id)
          revision_id = field(entry, :revision_id)
          target = field(entry, :target)
          excerpt = field(entry, :excerpt)
          source = sources[revision_id] || rollback(repo, :unlisted_evidence_revision)
          if !is_binary(evidence_id) or Map.has_key?(acc, evidence_id), do: rollback(repo, :invalid_evidence_id)
          if field(entry, :screenplay_id) != screenplay_id, do: rollback(repo, :foreign_evidence)

          value =
            case Fount.Target.resolve(source, target) do
              {:ok, item} -> item
              _ -> rollback(repo, :invalid_evidence_target)
            end

          text = if is_map(value), do: Map.get(value, :text), else: nil
          span = field(target, :span)
          span = if is_map(span), do: {field(span, :byte_start), field(span, :byte_end)}, else: span
          valid = if span, do: Fount.Writing.UTF8Span.verify(text, span, excerpt) == :ok, else: text == excerpt
          if !valid, do: rollback(repo, :evidence_excerpt_mismatch)
          Map.put(acc, evidence_id, entry)
        end)

      citations = field(payload, :citations) || []
      if Enum.any?(citations, &(!Map.has_key?(registry, &1))), do: rollback(repo, :uninspected_citation)

      if !is_binary(field(report, :fingerprint)) or !is_binary(field(report, :tool)),
        do: rollback(repo, :invalid_report)

      q(
        repo,
        "INSERT INTO analysis_reports(id,screenplay_id,primary_revision_id,session_id,tool,status,fingerprint,payload) VALUES($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5,$6,$7,$8::jsonb)",
        [
          id,
          screenplay_id,
          primary_id,
          field(report, :session_id),
          field(report, :tool),
          field(report, :status) || "complete",
          field(report, :fingerprint),
          json(payload)
        ]
      )

      Enum.each(source_ids, fn source_id ->
        q(
          repo,
          "INSERT INTO analysis_report_sources(screenplay_id,report_id,revision_id) VALUES($1::uuid,$2::uuid,$3::uuid)",
          [screenplay_id, id, source_id]
        )
      end)

      Map.put(report, :id, id)
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

  defp acceptance(repo, model, parent, actor, origin, operations, provenance, review, candidate_id \\ nil) do
    q(
      repo,
      "INSERT INTO acceptances(id,screenplay_id,base_revision_id,result_revision_id,candidate_id,actor,origin,operations,provenance,review) VALUES($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::uuid,$6,$7,$8::jsonb,$9::jsonb,$10::jsonb)",
      [
        ID.v4(),
        model.id,
        parent,
        model.revision.id,
        candidate_id,
        actor,
        to_string(origin),
        json(operations),
        json(provenance),
        json(review)
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
      Ecto.Adapters.SQL.query!(
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
               "primary_revision_id",
               "revision_id",
               "session_id"
             ] ->
          {:ok, id} = Ecto.UUID.load(value)
          {column, id}

        pair ->
          pair
      end)
    end)
  end

  defp rollback(repo, reason), do: repo.rollback(reason)
  defp transaction(repo, fun), do: repo.transaction(fun)
end
