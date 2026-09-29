defmodule FountRun.Control do
  @moduledoc "Durable owner steering for Phase 05 plan/policy snapshots and run lifecycle controls."

  alias Ecto.Adapters.SQL
  alias Fount.Writing.CanonicalJSON
  alias FountRun.{ActorContext, Persistence}

  @open_approval ~w(pending reviewed ready unknown)
  @terminal_run ~w(completed_candidate completed_accepted stopped failed)

  def update_plan(repo, run_id, attrs, %ActorContext{} = context, opts)
      when is_map(attrs) and is_list(opts) do
    with {:ok, command_id} <- command_id(opts),
         {:ok, expected_version} <- positive_version(opts, :expected_version) do
      tx(repo, fn ->
        update_plan_locked(repo, run_id, attrs, context, opts, command_id, expected_version)
      end)
    end
  end

  def update_plan(_repo, _run_id, _attrs, _context, _opts), do: {:error, :invalid_plan_update}

  def update_policy(repo, run_id, value, %ActorContext{} = context, opts)
      when is_map(value) and is_list(opts) do
    with {:ok, command_id} <- command_id(opts),
         {:ok, expected_version} <- positive_version(opts, :expected_version) do
      tx(repo, fn ->
        update_policy_locked(repo, run_id, value, context, command_id, expected_version)
      end)
    end
  end

  def update_policy(_repo, _run_id, _value, _context, _opts), do: {:error, :invalid_policy_update}

  defp update_plan_locked(repo, run_id, attrs, context, opts, command_id, expected_version) do
    run = locked_run!(repo, run_id, context)
    fingerprint = command_fingerprint(command_id, expected_version, attrs)

    case command_replay(repo, "fount_run_plans", run_id, command_id, fingerprint) do
      {:replay, snapshot} ->
        %{"run" => hydrate_run(repo, run), "plan" => snapshot, "replay" => true}

      :new ->
        current = plan_row(repo, run_id, run["current_plan_version"])

        if run["status"] in @terminal_run or successor_plan?(attrs, current) do
          create_successor!(repo, run, attrs, context, command_id, expected_version)
        else
          append_plan_update!(
            repo,
            run_id,
            attrs,
            context,
            opts,
            command_id,
            expected_version,
            fingerprint
          )
        end
    end
  end

  defp append_plan_update!(
         repo,
         run_id,
         attrs,
         context,
         opts,
         command_id,
         expected_version,
         fingerprint
       ) do
    plan =
      case Persistence.append_plan_snapshot(repo, run_id, attrs, context,
             expected_version: expected_version,
             reason: Keyword.get(opts, :reason, "owner_update"),
             command_id: command_id,
             command_fingerprint: fingerprint
           ) do
        {:ok, value} -> value
        {:error, reason} -> rollback(repo, reason)
      end

    refresh = invalidate_and_refresh!(repo, run_id, context, "plan", plan["version"])

    %{
      "run" => hydrate_run(repo, run_row(repo, run_id)),
      "plan" => plan,
      "refresh_step" => refresh,
      "replay" => false
    }
  end

  defp update_policy_locked(repo, run_id, value, context, command_id, expected_version) do
    run = locked_run!(repo, run_id, context)
    fingerprint = command_fingerprint(command_id, expected_version, value)

    case command_replay(repo, "fount_run_policies", run_id, command_id, fingerprint) do
      {:replay, snapshot} ->
        %{"run" => hydrate_run(repo, run), "policy" => snapshot, "replay" => true}

      :new ->
        if run["status"] in @terminal_run, do: rollback(repo, :terminal_run)

        append_policy_update!(
          repo,
          run_id,
          value,
          context,
          command_id,
          expected_version,
          fingerprint
        )
    end
  end

  defp append_policy_update!(
         repo,
         run_id,
         value,
         context,
         command_id,
         expected_version,
         fingerprint
       ) do
    policy =
      case Persistence.append_policy_snapshot(repo, run_id, value, context,
             expected_version: expected_version,
             command_id: command_id,
             command_fingerprint: fingerprint
           ) do
        {:ok, item} -> item
        {:error, reason} -> rollback(repo, reason)
      end

    refresh = invalidate_and_refresh!(repo, run_id, context, "policy", policy["version"])

    %{
      "run" => hydrate_run(repo, run_row(repo, run_id)),
      "policy" => policy,
      "refresh_step" => refresh,
      "replay" => false
    }
  end

  defp command_fingerprint(command_id, expected_version, payload),
    do:
      CanonicalJSON.hash(%{
        "command_id" => command_id,
        "expected_version" => expected_version,
        "payload" => payload
      })

  def pause(repo, run_id, %ActorContext{} = context) do
    tx(repo, fn ->
      run = locked_run!(repo, run_id, context)

      cond do
        run["status"] in @terminal_run ->
          rollback(repo, :terminal_run)

        run["pause_requested_at"] ->
          %{"run" => hydrate_run(repo, run), "replay" => true}

        true ->
          # A pause intentionally does not change the fencing token. A worker that already
          # owns the lease may checkpoint once; no new claim/dispatch is allowed afterwards.
          q!(
            repo,
            "UPDATE fount_runs SET pause_requested_at=now(),status='paused',lock_version=lock_version+1,updated_at=now() WHERE id=$1::text::uuid",
            [run_id]
          )

          event!(repo, run_id, context, "run_paused", %{})
          %{"run" => hydrate_run(repo, run_row(repo, run_id)), "replay" => false}
      end
    end)
  end

  def resume(repo, run_id, %ActorContext{} = context) do
    tx(repo, fn ->
      run = locked_run!(repo, run_id, context)

      cond do
        run["stop_requested_at"] ->
          rollback(repo, :stopped)

        is_nil(run["pause_requested_at"]) ->
          %{"run" => hydrate_run(repo, run), "replay" => true}

        true ->
          status = resume_status(repo, run_id)

          q!(
            repo,
            "UPDATE fount_runs SET pause_requested_at=NULL,status=$2,lock_version=lock_version+1,updated_at=now() WHERE id=$1::text::uuid",
            [run_id, status]
          )

          event!(repo, run_id, context, "run_resumed", %{"status" => status})
          %{"run" => hydrate_run(repo, run_row(repo, run_id)), "replay" => false}
      end
    end)
  end

  def stop(repo, run_id, %ActorContext{} = context) do
    tx(repo, fn ->
      run = locked_run!(repo, run_id, context)

      cond do
        run["stop_requested_at"] ->
          %{"run" => hydrate_run(repo, run), "replay" => true}

        run["status"] in @terminal_run ->
          # Stop races serialize on the Run row. Once delivery has made a completion
          # terminal, a later stop is a no-op and cannot erase acceptance/candidate state.
          %{"run" => hydrate_run(repo, run), "replay" => true, "terminal_winner" => run["status"]}

        true ->
          q!(
            repo,
            "UPDATE fount_run_steps SET status='cancelled',lease_owner=NULL,lease_token=NULL,lease_expires_at=NULL,heartbeat_at=NULL,updated_at=now() WHERE run_id=$1::text::uuid AND status IN ('queued','waiting','claimed')",
            [run_id]
          )

          q!(
            repo,
            "UPDATE fount_run_steps SET status='fenced',lease_owner=NULL,lease_token=NULL,lease_expires_at=NULL,heartbeat_at=NULL,updated_at=now() WHERE run_id=$1::text::uuid AND status='running'",
            [run_id]
          )

          q!(
            repo,
            "UPDATE fount_run_attempts SET outcome='fenced',redacted_error=$2::jsonb,ended_at=now() WHERE run_id=$1::text::uuid AND outcome='running'",
            [run_id, %{"reason" => "run_stopped"}]
          )

          fence_approval_attempts(repo, run_id, "run_stopped")
          supersede_pending_decisions(repo, run_id)

          q!(
            repo,
            "UPDATE fount_runs SET stop_requested_at=now(),pause_requested_at=NULL,status='stopped',active_step_id=NULL,current_fencing_token=current_fencing_token+1,lock_version=lock_version+1,updated_at=now() WHERE id=$1::text::uuid",
            [run_id]
          )

          event!(repo, run_id, context, "run_stopped", %{})
          %{"run" => hydrate_run(repo, run_row(repo, run_id)), "replay" => false}
      end
    end)
  end

  def mark_completion(repo, run_id, candidate_id, status, %ActorContext{} = context)
      when status in [
             "completed_candidate",
             "completed_accepted",
             "partial",
             "waiting_for_approval"
           ] do
    tx(repo, fn ->
      run = locked_run!(repo, run_id, context)
      if run["stop_requested_at"], do: rollback(repo, :stopped)

      q!(
        repo,
        "UPDATE fount_runs SET selected_candidate_id=COALESCE($2::text::uuid,selected_candidate_id),status=$3,stage='deliver',active_step_id=NULL,lock_version=lock_version+1,updated_at=now() WHERE id=$1::text::uuid",
        [run_id, candidate_id, status]
      )

      hydrate_run(repo, run_row(repo, run_id))
    end)
  end

  def current_head(repo, screenplay_id) do
    case one(
           repo,
           "SELECT head_revision_id::text AS id FROM screenplays WHERE id=$1::text::uuid",
           [screenplay_id]
         ) do
      nil -> {:error, :screenplay_not_found}
      row -> {:ok, row["id"]}
    end
  rescue
    _ in Postgrex.Error -> {:error, :storage_error}
  end

  defp successor_plan?(attrs, current) do
    base = value(attrs, "base_revision_id")
    scope = value(attrs, "scope")
    base != current["base_revision_id"] or scope != current["scope"]
  end

  defp create_successor!(repo, run, attrs, context, command_id, expected_version) do
    if expected_version != run["current_plan_version"],
      do: rollback(repo, {:stale_plan_version, run["current_plan_version"]})

    current_policy = policy_row(repo, run["id"], run["current_policy_version"])

    start_attrs =
      attrs
      |> stringify_keys()
      |> Map.put("screenplay_id", run["screenplay_id"])
      |> Map.put("policy", current_policy["policy"])
      |> Map.put("client_idempotency_key", "successor:" <> run["id"] <> ":" <> command_id)

    successor = unwrap!(repo, Persistence.start_run(repo, start_attrs, context))

    existing = run["superseding_run_id"]

    cond do
      existing && existing != successor["id"] ->
        rollback(repo, :successor_conflict)

      existing == successor["id"] ->
        %{
          "run" => hydrate_run(repo, run_row(repo, successor["id"])),
          "successor_of" => run["id"],
          "refresh_step" => existing_step(repo, successor["id"], "successor:" <> command_id),
          "replay" => true
        }

      true ->
        activate_successor!(repo, run, successor, context, command_id)
    end
  end

  defp activate_successor!(repo, run, successor, context, command_id) do
    q!(
      repo,
      "UPDATE fount_runs SET superseding_run_id=$2::text::uuid,current_fencing_token=current_fencing_token+1,lock_version=lock_version+1,updated_at=now() WHERE id=$1::text::uuid",
      [run["id"], successor["id"]]
    )

    q!(
      repo,
      "UPDATE fount_runs SET parent_run_id=$2::text::uuid,iteration=$3,updated_at=now() WHERE id=$1::text::uuid",
      [successor["id"], run["id"], run["iteration"] || 0]
    )

    fence_approval_attempts(repo, run["id"], "successor_created")
    supersede_pending_decisions(repo, run["id"])
    successor_plan = plan_row(repo, successor["id"], successor["current_plan_version"] || 1)
    request = successor_request(repo, run["id"], successor_plan)
    first_step = create_successor_step!(repo, run, successor, request, context, command_id)

    %{
      "run" => hydrate_run(repo, run_row(repo, successor["id"])),
      "successor_of" => run["id"],
      "refresh_step" => first_step,
      "replay" => false
    }
  end

  defp create_successor_step!(_repo, _run, _successor, nil, _context, _command_id), do: nil

  defp create_successor_step!(repo, run, successor, request, context, command_id) do
    step =
      create_step!(
        repo,
        successor["id"],
        "intake",
        request,
        nil,
        run["iteration"] || 0,
        "successor:" <> command_id,
        context
      )

    q!(
      repo,
      "UPDATE fount_runs SET status='queued',stage='intake',updated_at=now() WHERE id=$1::text::uuid",
      [successor["id"]]
    )

    step
  end

  defp unwrap!(_repo, {:ok, value}), do: value
  defp unwrap!(repo, {:error, reason}), do: rollback(repo, reason)

  defp existing_step(repo, run_id, key),
    do:
      one(
        repo,
        "SELECT * FROM fount_run_steps WHERE run_id=$1::text::uuid AND idempotency_key=$2",
        [run_id, key]
      )

  defp successor_request(repo, run_id, plan) do
    case one(
           repo,
           "SELECT request FROM fount_run_steps WHERE run_id=$1::text::uuid AND stage='intake' ORDER BY inserted_at,id LIMIT 1",
           [run_id]
         ) do
      nil -> nil
      %{"request" => request} -> put_successor_plan(request, plan)
    end
  end

  defp put_successor_plan(%{"workshop_request" => wr} = request, plan) when is_map(wr) do
    wr =
      wr
      |> Map.put("base_revision_id", plan["base_revision_id"])
      |> Map.put("instruction", plan["goal"])
      |> Map.put("selection", plan["scope"])
      |> Map.put("constraints", plan["constraints"] || [])

    request
    |> Map.put("workshop_request", wr)
    |> Map.drop(
      ~w(investigation_request investigation_session_id strategy_session_id selected_strategy_ids decision_id candidate_ids source_candidate_id finding report_ids uncertainty lineage check_set_fingerprint)
    )
  end

  defp put_successor_plan(request, _plan), do: request

  defp invalidate_and_refresh!(repo, run_id, context, kind, version) do
    supersede_pending_decisions(repo, run_id)
    fence_approval_attempts(repo, run_id, kind <> "_changed")

    q!(
      repo,
      "UPDATE fount_run_steps s SET status='fenced',lease_owner=NULL,lease_token=NULL,lease_expires_at=NULL,heartbeat_at=NULL,updated_at=now() FROM fount_runs r WHERE s.run_id=r.id AND r.id=$1::text::uuid AND s.status IN ('queued','waiting','claimed','running') AND (s.plan_version<>r.current_plan_version OR s.policy_version<>r.current_policy_version)",
      [run_id]
    )

    q!(
      repo,
      "UPDATE fount_run_attempts a SET outcome='fenced',redacted_error=$2::jsonb,ended_at=now() FROM fount_run_steps s,fount_runs r WHERE a.step_id=s.id AND a.run_id=s.run_id AND s.run_id=r.id AND r.id=$1::text::uuid AND a.outcome='running' AND (s.plan_version<>r.current_plan_version OR s.policy_version<>r.current_policy_version)",
      [run_id, %{"reason" => kind <> "_changed"}]
    )

    run = run_row(repo, run_id)

    latest_request =
      one(
        repo,
        "SELECT request FROM fount_run_steps WHERE run_id=$1::text::uuid ORDER BY inserted_at DESC,id DESC LIMIT 1",
        [run_id]
      )

    intake_request =
      one(
        repo,
        "SELECT request FROM fount_run_steps WHERE run_id=$1::text::uuid AND stage='intake' ORDER BY inserted_at,id LIMIT 1",
        [run_id]
      )

    step = refresh_step!(repo, run, kind, version, intake_request, latest_request, context)

    if step do
      q!(
        repo,
        "UPDATE fount_runs SET status='queued',stage=$2,active_step_id=NULL,updated_at=now() WHERE id=$1::text::uuid",
        [run_id, step["stage"]]
      )
    else
      q!(
        repo,
        "UPDATE fount_runs SET status='partial',active_step_id=NULL,updated_at=now() WHERE id=$1::text::uuid",
        [run_id]
      )
    end

    event!(repo, run_id, context, kind <> "_changed", %{
      "version" => version,
      "refresh_step_id" => step && step["id"]
    })

    step
  end

  defp refresh_step!(repo, run, kind, version, intake_request, latest_request, context) do
    key = "control-refresh:" <> kind <> ":" <> to_string(version)

    cond do
      kind == "plan" and intake_request ->
        plan = plan_row(repo, run["id"], run["current_plan_version"])
        request = refresh_plan_request(intake_request["request"], plan)
        create_step!(repo, run["id"], "intake", request, nil, run["iteration"], key, context)

      (kind == "policy" and run["selected_candidate_id"]) && latest_request ->
        create_step!(
          repo,
          run["id"],
          "check",
          latest_request["request"],
          run["selected_candidate_id"],
          run["iteration"],
          key,
          context
        )

      latest_request ->
        create_step!(
          repo,
          run["id"],
          "intake",
          latest_request["request"],
          nil,
          run["iteration"],
          key,
          context
        )

      true ->
        nil
    end
  end

  defp refresh_plan_request(%{"workshop_request" => request} = envelope, plan)
       when is_map(request) do
    request =
      request
      |> Map.put("base_revision_id", plan["base_revision_id"])
      |> Map.put("instruction", plan["goal"])
      |> Map.put("constraints", plan["constraints"] || [])

    envelope
    |> Map.put("workshop_request", request)
    |> Map.drop(
      ~w(investigation_request investigation_session_id strategy_session_id selected_strategy_ids decision_id candidate_ids source_candidate_id finding report_ids uncertainty lineage check_set_fingerprint)
    )
  end

  defp refresh_plan_request(envelope, _plan), do: envelope

  defp create_step!(repo, run_id, stage, request, candidate_id, iteration, key, context) do
    attrs = %{
      "stage" => stage,
      "iteration" => iteration,
      "branch_id" => "main",
      "input_revision_id" => nil,
      "input_candidate_id" => candidate_id,
      "request" => request,
      "idempotency_key" => key
    }

    case Persistence.create_step(repo, run_id, attrs, context) do
      {:ok, step} -> step
      {:error, reason} -> rollback(repo, reason)
    end
  end

  defp supersede_pending_decisions(repo, run_id) do
    q!(
      repo,
      "UPDATE fount_run_decisions SET status='superseded',updated_at=now() WHERE run_id=$1::text::uuid AND status='pending'",
      [run_id]
    )
  end

  defp fence_approval_attempts(repo, run_id, reason) do
    q!(
      repo,
      "UPDATE fount_run_approval_attempts SET outcome='fenced',outcome_reason=$2,finished_at=now(),updated_at=now() WHERE run_id=$1::text::uuid AND outcome = ANY($3::text[])",
      [run_id, reason, @open_approval]
    )
  end

  defp resume_status(repo, run_id) do
    cond do
      count(
        repo,
        "SELECT count(*) AS n FROM fount_run_decisions WHERE run_id=$1::text::uuid AND status='pending'",
        [run_id]
      ) > 0 ->
        "waiting_for_decision"

      count(
        repo,
        "SELECT count(*) AS n FROM fount_run_approval_attempts WHERE run_id=$1::text::uuid AND outcome = ANY($2::text[])",
        [run_id, @open_approval]
      ) > 0 ->
        "waiting_for_approval"

      count(
        repo,
        "SELECT count(*) AS n FROM fount_run_steps WHERE run_id=$1::text::uuid AND status IN ('queued','waiting','running','claimed')",
        [run_id]
      ) > 0 ->
        "queued"

      true ->
        "partial"
    end
  end

  defp command_replay(repo, table, run_id, command_id, fingerprint) do
    sql = "SELECT * FROM " <> table <> " WHERE run_id=$1::text::uuid AND command_key=$2"

    case one(repo, sql, [run_id, command_id]) do
      nil -> :new
      %{"command_fingerprint" => ^fingerprint} = row -> {:replay, row}
      _ -> rollback(repo, :command_id_conflict)
    end
  end

  defp command_id(opts) do
    case Keyword.get(opts, :command_id) do
      value when is_binary(value) ->
        if String.trim(value) == "", do: {:error, :command_id_required}, else: {:ok, value}

      _ ->
        {:error, :command_id_required}
    end
  end

  defp positive_version(opts, key) do
    case Keyword.get(opts, key) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _ -> {:error, {:invalid_option, key}}
    end
  end

  defp event!(repo, run_id, context, type, payload) do
    case Persistence.append_event(repo, run_id, type, payload, context) do
      {:ok, event} -> event
      {:error, reason} -> rollback(repo, reason)
    end
  end

  defp locked_run!(repo, run_id, context) do
    run =
      one(repo, "SELECT * FROM fount_runs WHERE id=$1::text::uuid FOR UPDATE", [run_id]) ||
        rollback(repo, :not_found)

    :ok = authorize!(repo, run, context)
    run
  end

  defp authorize!(repo, run, context) do
    case ActorContext.authorize(context, :manage_run, run["screenplay_id"]) do
      :ok -> :ok
      {:error, reason} -> rollback(repo, reason)
    end

    if {run["owner_type"], run["owner_id"]} !=
         {Atom.to_string(context.owner.type), context.owner.id},
       do: rollback(repo, :unauthorized)

    :ok
  end

  defp hydrate_run(repo, run) do
    run
    |> Map.put("plan", plan_row(repo, run["id"], run["current_plan_version"]))
    |> Map.put("policy", policy_row(repo, run["id"], run["current_policy_version"]))
  end

  defp run_row(repo, run_id),
    do: one(repo, "SELECT * FROM fount_runs WHERE id=$1::text::uuid", [run_id])

  defp plan_row(repo, run_id, version),
    do:
      one(repo, "SELECT * FROM fount_run_plans WHERE run_id=$1::text::uuid AND version=$2", [
        run_id,
        version
      ])

  defp policy_row(repo, run_id, version),
    do:
      one(repo, "SELECT * FROM fount_run_policies WHERE run_id=$1::text::uuid AND version=$2", [
        run_id,
        version
      ])

  defp count(repo, sql, params), do: one(repo, sql, params)["n"]

  defp one(repo, sql, params) do
    result = q!(repo, sql, params)

    case result.rows do
      [row | _] -> Persistence.row_map(result.columns, row)
      [] -> nil
    end
  end

  defp q!(repo, sql, params), do: SQL.query!(repo, sql, params)

  defp tx(repo, fun) do
    case repo.transaction(fun) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ in Postgrex.Error -> {:error, :storage_error}
  end

  defp rollback(repo, reason), do: repo.rollback(reason)

  defp value(map, "base_revision_id"),
    do: Map.get(map, "base_revision_id", Map.get(map, :base_revision_id))

  defp value(map, "scope"), do: Map.get(map, "scope", Map.get(map, :scope))
  defp stringify_keys(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
end
