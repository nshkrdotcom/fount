defmodule FountWeb.Authoring do
  @moduledoc "Trusted host boundary for Phase 05 drafts, manual candidates, exact acceptance, and AI Run handoff."

  alias Fount.Screenplay
  alias Fount.Screenplay.SourceReconciler
  alias Fount.Writing.{Approval, Authority, Principal}
  alias FountWeb.AuthoringStore

  @doc "Loads owner/project/canonical head and opens the owner recovery draft."
  def open_workspace(owner, project_id) when is_binary(owner) and is_binary(project_id) do
    with {:ok, project} <- FountWeb.Store.project(Fount.Repo, owner, project_id),
         {:ok, base} <- Fount.Persistence.load(Fount.Repo, project["key"]),
         true <- base.id == project["screenplay_id"],
         {:ok, draft} <- AuthoringStore.open(Fount.Repo, owner, project, base),
         {:ok, preview} <-
           preview(base, draft["raw_source"],
             prior_source: draft["last_valid_source"],
             identity_anchors: draft["identity_anchors"] || []
           ) do
      {:ok, %{project: project, base: base, draft: draft, preview: preview}}
    else
      false -> {:error, :project_screenplay_mismatch}
      {:error, _} = error -> error
    end
  end

  @doc "Reconciles raw source for preview without writing canon or draft storage."
  def preview(%Screenplay{} = base, raw, opts \\ []) when is_binary(raw) and is_list(opts) do
    opts = Keyword.put(opts, :max_bytes, AuthoringStore.limits().max_source_bytes)

    case SourceReconciler.reconcile(base, raw, opts) do
      {:ok, result} ->
        {:ok, Map.put(result, :valid?, true)}

      {:error, {:invalid_source, blockers, diagnostics}} ->
        with {:ok, last_valid} <-
               SourceReconciler.reconcile(
                 base,
                 Keyword.get(opts, :prior_source, Screenplay.to_fountain(base)),
                 opts
               ) do
          {:ok,
           Map.merge(last_valid, %{valid?: false, blockers: blockers, diagnostics: diagnostics})}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Durably saves raw source with optimistic draft versioning; invalid source is retained verbatim."
  def save_draft(owner, draft_id, expected_version, raw, reason \\ "manual", reconcile_opts \\ []) do
    with {:ok, draft} <- AuthoringStore.get(Fount.Repo, owner, draft_id),
         {:ok, base} <- load_bound_base(draft),
         {:ok, result} <-
           preview(
             base,
             raw,
             Keyword.merge(
               [
                 prior_source: draft["last_valid_source"],
                 identity_anchors: draft["identity_anchors"] || []
               ],
               reconcile_opts
             )
           ) do
      attrs =
        if result.valid? do
          %{
            valid?: true,
            fidelity: result.fidelity,
            identity_anchors: result.identity_anchors,
            reason: reason
          }
        else
          %{valid?: false, fidelity: %{}, reason: reason}
        end

      case AuthoringStore.save(Fount.Repo, owner, draft_id, expected_version, raw, attrs) do
        {:ok, saved} -> {:ok, saved, result}
        {:error, _} = error -> error
      end
    end
  end

  @doc "Explicitly rebases draft recovery state to the current accepted head; never accepts content."
  def rebase(owner, draft_id, expected_version) do
    with {:ok, draft} <- AuthoringStore.get(Fount.Repo, owner, draft_id),
         {:ok, project} <- FountWeb.Store.project(Fount.Repo, owner, draft["project_id"]),
         {:ok, head} <- Fount.Persistence.load(Fount.Repo, project["key"]),
         true <- head.id == draft["screenplay_id"] do
      AuthoringStore.rebase(Fount.Repo, owner, draft_id, expected_version, head.revision.id)
    else
      false -> {:error, :project_screenplay_mismatch}
      {:error, _} = error -> error
    end
  end

  @doc "Applies one existing validated screenplay operation, then stores the exact resulting Fountain source."
  def structural_edit(owner, draft_id, expected_version, %Screenplay{} = current, operation) do
    with {:ok, next, changes} <- Screenplay.apply(current, [operation], actor: "writer:#{owner}"),
         raw <- Screenplay.to_fountain(next),
         {:ok, saved, _preview} <-
           save_draft(owner, draft_id, expected_version, raw, "structural_edit",
             prior_source: raw,
             identity_anchors: Fount.Identity.anchors(next.ir)
           ) do
      {:ok, saved, next, changes}
    end
  end

  @doc "Stores the current valid draft as a candidate bound to its accepted base; canonical head is unchanged."
  def save_candidate(owner, draft_id, expected_version) do
    with {:ok, draft} <- AuthoringStore.get(Fount.Repo, owner, draft_id),
         :ok <- exact_version(draft, expected_version),
         :ok <- active_draft(draft),
         {:ok, project} <- FountWeb.Store.project(Fount.Repo, owner, draft["project_id"]),
         {:ok, head} <- Fount.Persistence.load(Fount.Repo, project["key"]),
         :ok <- exact_base(draft, head) do
      replay_or_save_candidate(owner, draft, expected_version)
    end
  end

  defp replay_or_save_candidate(
         _owner,
         %{"saved_candidate_id" => id, "saved_candidate_version" => version} = draft,
         version
       )
       when is_binary(id) do
    with {:ok, candidate} <- Fount.Persistence.candidate(Fount.Repo, id) do
      {:ok, draft, %{id: candidate["id"], screenplay: candidate["screenplay"]},
       draft["last_valid_fidelity"] || %{}}
    end
  end

  defp replay_or_save_candidate(owner, draft, expected_version) do
    with {:ok, project} <- FountWeb.Store.project(Fount.Repo, owner, draft["project_id"]),
         {:ok, head} <- Fount.Persistence.load(Fount.Repo, project["key"]),
         :ok <- exact_base(draft, head),
         ids <- candidate_ids(draft),
         {:ok, reconciled} <-
           SourceReconciler.reconcile(head, draft["raw_source"],
             revision_id: ids.revision_id,
             actor: "writer:#{owner}",
             message: "interactive draft candidate",
             max_bytes: AuthoringStore.limits().max_source_bytes,
             prior_source: draft["last_valid_source"],
             identity_anchors: draft["identity_anchors"] || []
           ),
         true <- reconciled.fidelity["exact_source_round_trip"],
         {:ok, candidate} <-
           Fount.Persistence.save_edit_candidate(
             Fount.Repo,
             project["key"],
             reconciled.screenplay,
             expected_revision: draft["base_revision_id"],
             session_id: ids.session_id,
             candidate_id: ids.candidate_id,
             label: "Interactive edit"
           ),
         {:ok, bound} <-
           AuthoringStore.bind_candidate(
             Fount.Repo,
             owner,
             draft["id"],
             expected_version,
             candidate.id
           ) do
      {:ok, bound, candidate, reconciled.fidelity}
    else
      false -> {:error, :source_fidelity_failed}
      {:error, _} = error -> error
    end
  end

  @doc "Exact typed human approval of the draft-bound candidate. This is the only authoring path that advances canon."
  def accept_candidate(owner, draft_id, candidate_id, approval_id) do
    with {:ok, draft} <- AuthoringStore.get(Fount.Repo, owner, draft_id),
         true <- draft["saved_candidate_id"] == candidate_id,
         true <- draft["saved_candidate_version"] == draft["version"],
         {:ok, candidate} <- Fount.Persistence.candidate(Fount.Repo, candidate_id),
         true <- candidate["screenplay_id"] == draft["screenplay_id"],
         true <- candidate["base_revision_id"] == draft["base_revision_id"],
         {:ok, principal} <- Principal.new(:human, owner),
         {:ok, authority} <- Authority.new(principal, draft["screenplay_id"], [:approve]),
         {:ok, approval} <- Approval.direct(candidate, principal, approval_id),
         {:ok, accepted} <-
           Fount.Persistence.accept_candidate(Fount.Repo, candidate_id,
             approval: approval,
             authority: authority
           ),
         {:ok, _draft} <- AuthoringStore.mark_accepted(Fount.Repo, owner, draft_id, candidate_id) do
      {:ok, accepted}
    else
      false -> {:error, :candidate_not_bound_to_current_draft}
      {:error, _} = error -> error
    end
  end

  @doc "Starts AI assistance only from a valid, durably saved manual candidate via the existing FountRun path."
  def start_ai_assist(owner, draft_id, command_id) do
    with {:ok, draft} <- AuthoringStore.get(Fount.Repo, owner, draft_id),
         candidate_id when is_binary(candidate_id) <- draft["saved_candidate_id"],
         true <- draft["saved_candidate_version"] == draft["version"],
         {:ok, result} <-
           FountWeb.Launch.create_from_candidate(owner, draft["project_id"], candidate_id, %{
             "command_id" => command_id
           }),
         {:ok, _} <- FountWeb.Store.mark_launched(Fount.Repo, owner, result.run["id"]),
         {:ok, access} <- FountWeb.Store.run_access(Fount.Repo, owner, result.run["id"]),
         {:ok, _pid} <- normalize_started(FountWeb.WorkerSupervisor.start_run(access)) do
      {:ok, result}
    else
      nil -> {:error, :saved_candidate_required}
      false -> {:error, :saved_candidate_stale}
      {:error, _} = error -> error
    end
  end

  defp load_bound_base(draft),
    do:
      Fount.Persistence.load_revision(
        Fount.Repo,
        draft["screenplay_id"],
        draft["base_revision_id"]
      )

  defp active_draft(%{"status" => "active"}), do: :ok
  defp active_draft(_), do: {:error, :draft_not_active}

  defp exact_version(draft, version) do
    if draft["version"] == version, do: :ok, else: {:error, {:stale_draft, draft}}
  end

  defp exact_base(draft, head) do
    if head.id == draft["screenplay_id"] and head.revision.id == draft["base_revision_id"],
      do: :ok,
      else: {:error, {:stale_base, head.revision.id}}
  end

  defp candidate_ids(draft) do
    identity =
      [draft["base_revision_id"], draft["version"], draft["source_sha256"]] |> Enum.join(":")

    %{
      revision_id: Fount.ID.v5(draft["id"], "revision:" <> identity),
      session_id: Fount.ID.v5(draft["id"], "session:" <> identity),
      candidate_id: Fount.ID.v5(draft["id"], "candidate:" <> identity)
    }
  end

  defp normalize_started({:ok, pid}), do: {:ok, pid}
  defp normalize_started({:error, {:already_started, pid}}), do: {:ok, pid}
  defp normalize_started({:error, _} = error), do: error
end
