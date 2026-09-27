defmodule Fount.Persistence.Analysis do
  @moduledoc """
  Durable storage primitives for derived screenplay analysis.

  The module stores data only. It does not interpret measurements, choose a cache
  identity, recompute dramatic state, call providers, or change canonical screenplay
  revisions. Those policies remain in Observe and Intelligence.
  """

  alias Ecto.Adapters.SQL
  alias Fount.ID
  alias Fount.Screenplay.Model

  @run_statuses ~w(running complete partial failed)
  @asset_kinds ~w(lens calibration playbook genre_pack)
  @forbidden_secret_keys ~w(api_key apikey authorization access_token refresh_token password secret credentials credential token headers base_url endpoint)

  @doc "Stores one immutable content-addressed analysis asset. Enablement is explicit."
  def save_asset(repo, asset) when is_map(asset) do
    with :ok <- valid_asset(asset),
         :ok <- secret_free(asset) do
      transaction(repo, fn -> persist_asset(repo, asset) end)
    end
  end

  def save_asset(_repo, _asset), do: {:error, :invalid_analysis_asset}

  defp persist_asset(repo, asset) do
    scope_id = field(asset, :scope_id)
    kind = field(asset, :kind)
    logical_id = field(asset, :logical_id)
    sha = field(asset, :sha256)

    case one(
           repo,
           "SELECT * FROM analysis_assets WHERE scope_id=$1 AND kind=$2 AND logical_id=$3 AND sha256=$4",
           [scope_id, kind, logical_id, sha]
         ) do
      nil ->
        id = field(asset, :id) || ID.v4()

        q(
          repo,
          "INSERT INTO analysis_assets(id,screenplay_id,scope_id,kind,logical_id,trust,source,content,sha256,parent_id,enabled) VALUES($1::uuid,$2::uuid,$3,$4,$5,$6,$7::jsonb,$8::jsonb,$9,$10::uuid,$11)",
          [
            id,
            field(asset, :screenplay_id),
            scope_id,
            kind,
            logical_id,
            field(asset, :trust),
            json(field(asset, :source) || %{}),
            json(field(asset, :content)),
            sha,
            field(asset, :parent_id),
            field(asset, :enabled) == true
          ]
        )

        asset
        |> Map.new(fn {key, value} -> {to_string(key), value} end)
        |> Map.put("id", id)

      row ->
        row
    end
  end

  @doc "Enables or disables an installed asset without mutating its content identity."
  def set_asset_enabled(repo, id, enabled) when is_binary(id) and is_boolean(enabled) do
    case one(repo, "SELECT id FROM analysis_assets WHERE id=$1::uuid", [id]) do
      nil ->
        {:error, :not_found}

      _ ->
        q(repo, "UPDATE analysis_assets SET enabled=$2 WHERE id=$1::uuid", [id, enabled])
        {:ok, enabled}
    end
  end

  def set_asset_enabled(_repo, _id, _enabled), do: {:error, :invalid_analysis_asset}

  @doc "Loads one exact asset identity; no latest-version or numeric compatibility lookup exists."
  def asset(repo, scope_id, kind, logical_id, sha256)
      when is_binary(scope_id) and is_binary(kind) and is_binary(logical_id) and is_binary(sha256) do
    case one(
           repo,
           "SELECT * FROM analysis_assets WHERE scope_id=$1 AND kind=$2 AND logical_id=$3 AND sha256=$4",
           [scope_id, kind, logical_id, sha256]
         ) do
      nil -> {:error, :not_found}
      row -> {:ok, row}
    end
  end

  @doc "Starts a durable analysis run tied to an exact screenplay revision."
  def start_run(repo, run) when is_map(run) do
    with :ok <- valid_run(run),
         :ok <- secret_free(run) do
      transaction(repo, fn -> persist_run(repo, run) end)
    end
  end

  def start_run(_repo, _run), do: {:error, :invalid_analysis_run}

  defp persist_run(repo, run) do
    id = field(run, :id) || ID.v4()

    case one(repo, "SELECT * FROM analysis_runs WHERE id=$1::uuid", [id]) do
      nil ->
        q(
          repo,
          "INSERT INTO analysis_runs(id,screenplay_id,revision_id,revision_content_sha256,session_id,candidate_id,playbook,playbook_sha256,status,concern,intent,scope,privacy_namespace,preflight,metadata) VALUES($1::uuid,$2::uuid,$3::uuid,$4,$5::uuid,$6::uuid,$7,$8,$9,$10::jsonb,$11::jsonb,$12::jsonb,$13,$14::jsonb,$15::jsonb)",
          run_params(run, id)
        )

        Map.put(run, :id, id)

      existing ->
        if run_identity(existing) == run_identity(run),
          do: existing,
          else: rollback(repo, :analysis_run_identity_conflict)
    end
  end

  defp run_params(run, id) do
    [id] ++
      Enum.map(
        ~w(screenplay_id revision_id revision_content_sha256 session_id candidate_id playbook playbook_sha256)a,
        &field(run, &1)
      ) ++
      [
        field(run, :status) || "running",
        json(field(run, :concern) || %{}),
        json(field(run, :intent) || %{}),
        json(field(run, :scope) || %{}),
        field(run, :privacy_namespace),
        json(field(run, :preflight) || %{}),
        json(field(run, :metadata) || %{})
      ]
  end

  @doc "Finishes a run. Summary/resource usage stay advisory derived history."
  def finish_run(repo, id, attrs) when is_binary(id) and is_map(attrs) do
    status = field(attrs, :status)

    with true <- status in ~w(complete partial failed),
         :ok <- secret_free(attrs),
         %{} <- one(repo, "SELECT id FROM analysis_runs WHERE id=$1::uuid", [id]) do
      q(
        repo,
        "UPDATE analysis_runs SET status=$2,output_contract_id=$3,output_contract_sha256=$4,resource_usage=$5::jsonb,summary=$6::jsonb,result=$7::jsonb,metadata=$8::jsonb,finished_at=now() WHERE id=$1::uuid",
        [
          id,
          status,
          field(attrs, :output_contract_id),
          field(attrs, :output_contract_sha256),
          json(field(attrs, :resource_usage) || %{}),
          json(field(attrs, :summary) || %{}),
          json(field(attrs, :result) || %{}),
          json(field(attrs, :metadata) || %{})
        ]
      )

      run(repo, id)
    else
      false -> {:error, :invalid_analysis_run}
      {:error, _} = error -> error
      nil -> {:error, :not_found}
      _ -> {:error, :invalid_analysis_run}
    end
  end

  def finish_run(_repo, _id, _attrs), do: {:error, :invalid_analysis_run}

  def run(repo, id) when is_binary(id) do
    case one(repo, "SELECT * FROM analysis_runs WHERE id=$1::uuid", [id]) do
      nil -> {:error, :not_found}
      row -> {:ok, row}
    end
  end

  def runs_for_session(repo, screenplay_id, session_id) do
    all(
      repo,
      "SELECT * FROM analysis_runs WHERE screenplay_id=$1::uuid AND session_id=$2::uuid ORDER BY inserted_at,id",
      [screenplay_id, session_id]
    )
  end

  @doc "Lists fresh revision-bound observations recorded for one durable analysis run."
  def observations_for_run(repo, run_id) when is_binary(run_id) do
    all(
      repo,
      "SELECT * FROM analysis_observations WHERE analysis_run_id=$1::uuid ORDER BY inserted_at,id",
      [run_id]
    )
  end

  @doc "Lists declared reverse-dependency rows for one durable analysis run."
  def dependencies_for_run(repo, run_id) when is_binary(run_id) do
    all(
      repo,
      "SELECT id,screenplay_id,subject_kind,subject_id,dependency_key,analysis_run_id,inserted_at FROM analysis_dependencies WHERE analysis_run_id=$1::uuid ORDER BY subject_kind,subject_id,dependency_key",
      [run_id]
    )
  end

  @doc "Returns the complete durable audit bundle for one run without consulting cache rows."
  def audit_bundle(repo, id) when is_binary(id) do
    with {:ok, stored_run} <- run(repo, id) do
      {:ok,
       %{
         "run" => stored_run,
         "observations" => observations_for_run(repo, id),
         "dependencies" => dependencies_for_run(repo, id)
       }}
    end
  end

  @doc "Durable actual usage history for later longitudinal estimates."
  def usage_history(repo, screenplay_id, playbook, opts \\ []) do
    limit = min(max(Keyword.get(opts, :limit, 50), 1), 500)

    all(
      repo,
      "SELECT id,revision_id,session_id,playbook,status,resource_usage,inserted_at FROM analysis_runs WHERE screenplay_id=$1::uuid AND playbook=$2 AND status IN ('complete','partial') ORDER BY inserted_at DESC,id LIMIT $3",
      [screenplay_id, playbook, limit]
    )
  end

  @doc "Reads one durable MeasurementResult cache entry under its explicit privacy namespace."
  def cache_get(repo, privacy_namespace, cache_key)
      when is_binary(privacy_namespace) and privacy_namespace != "" and is_binary(cache_key) do
    rows =
      all(
        repo,
        "SELECT payload FROM analysis_measurement_results WHERE privacy_namespace=$1 AND cache_key=$2 ORDER BY ordinal",
        [privacy_namespace, cache_key]
      )

    case rows do
      [] ->
        :miss

      rows ->
        q(
          repo,
          "UPDATE analysis_measurement_results SET last_accessed_at=now(),access_count=access_count+1 WHERE privacy_namespace=$1 AND cache_key=$2",
          [privacy_namespace, cache_key]
        )

        {:hit, Enum.map(rows, & &1["payload"])}
    end
  end

  def cache_get(_repo, _privacy_namespace, _cache_key), do: :miss

  @doc "Inserts an immutable cache entry. Existing content is never overwritten by a newer revision."
  def cache_put(repo, privacy_namespace, cache_key, results)
      when is_binary(privacy_namespace) and privacy_namespace != "" and is_binary(cache_key) and
             is_list(results) and results != [] do
    with :ok <- valid_cache_results(results, cache_key),
         :ok <- secret_free(results) do
      transaction(repo, fn -> persist_cache(repo, privacy_namespace, cache_key, results) end)
    end
  end

  def cache_put(_repo, _privacy_namespace, _cache_key, _results),
    do: {:error, :invalid_analysis_cache_entry}

  defp persist_cache(repo, namespace, key, results) do
    case cache_get(repo, namespace, key) do
      :miss ->
        Enum.with_index(results)
        |> Enum.each(fn {result, ordinal} ->
          q(
            repo,
            "INSERT INTO analysis_measurement_results(cache_key,ordinal,result_id,privacy_namespace,measurement_spec_sha256,input_sha256,semantic_execution_sha256,output_contract_id,output_contract_sha256,provider_fingerprint,payload) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::jsonb,$11::jsonb)",
            [
              key,
              ordinal,
              field(result, :id),
              namespace,
              field(result, :measurement_spec_sha256),
              field(result, :input_sha256),
              field(result, :semantic_execution_sha256),
              field(result, :output_contract_id),
              field(result, :output_contract_sha256),
              json(field(result, :provider_fingerprint)),
              json(Model.plain(result))
            ]
          )
        end)

        :ok

      {:hit, stored} ->
        if stored == Enum.map(results, &Model.plain/1),
          do: :ok,
          else: rollback(repo, :analysis_cache_identity_conflict)
    end
  end

  @doc "Explicit resource eviction. It removes cache rows only and is never called by revision edits."
  def evict_cache(repo, privacy_namespace, keep_entries)
      when is_binary(privacy_namespace) and privacy_namespace != "" and is_integer(keep_entries) and
             keep_entries >= 0 do
    result =
      q(
        repo,
        "WITH keys AS (SELECT cache_key,max(last_accessed_at) AS touched FROM analysis_measurement_results WHERE privacy_namespace=$1 GROUP BY cache_key), doomed AS (SELECT cache_key FROM keys ORDER BY touched DESC,cache_key OFFSET $2) DELETE FROM analysis_measurement_results r USING doomed d WHERE r.privacy_namespace=$1 AND r.cache_key=d.cache_key",
        [privacy_namespace, keep_entries]
      )

    {:ok, result.num_rows}
  end

  def evict_cache(_repo, _privacy_namespace, _keep_entries), do: {:error, :invalid_cache_eviction}

  @doc "Stores fresh revision-bound observations for a durable analysis run."
  def save_observations(repo, run_id, screenplay_id, revision_id, observations)
      when is_binary(run_id) and is_binary(screenplay_id) and is_binary(revision_id) and
             is_list(observations) do
    with :ok <- valid_observations(observations, screenplay_id, revision_id),
         :ok <- secret_free(observations),
         {:ok, run} <- run(repo, run_id),
         true <- run["screenplay_id"] == screenplay_id,
         true <- run["revision_id"] == revision_id do
      transaction(repo, fn ->
        Enum.each(observations, &insert_observation(repo, run_id, screenplay_id, revision_id, &1))
        observations
      end)
    else
      false -> {:error, :analysis_run_revision_mismatch}
      error -> error
    end
  end

  def save_observations(_repo, _run_id, _screenplay_id, _revision_id, _observations),
    do: {:error, :invalid_analysis_observation}

  defp insert_observation(repo, run_id, screenplay_id, revision_id, observation) do
    id = field(observation, :id)
    result = field(observation, :result) || %{}
    result_id = field(result, :id) || field(observation, :result_id)
    provenance = field(observation, :provenance) || %{}
    request_id = field(provenance, :request_id)

    case one(repo, "SELECT payload FROM analysis_observations WHERE id=$1", [id]) do
      nil ->
        q(
          repo,
          "INSERT INTO analysis_observations(id,analysis_run_id,screenplay_id,revision_id,request_id,result_id,kind,target,evidence,dependencies,payload) VALUES($1,$2::uuid,$3::uuid,$4::uuid,$5,$6,$7,$8::jsonb,$9::jsonb,$10::jsonb,$11::jsonb)",
          observation_params(observation, id, run_id, screenplay_id, revision_id, request_id, result_id)
        )

      %{"payload" => payload} ->
        if payload != Model.plain(observation), do: rollback(repo, :analysis_observation_identity_conflict)
    end
  end

  defp observation_params(observation, id, run_id, screenplay_id, revision_id, request_id, result_id) do
    [
      id,
      run_id,
      screenplay_id,
      revision_id,
      request_id,
      result_id,
      to_string(field(observation, :kind)),
      json(field(observation, :target) || %{}),
      json(field(observation, :evidence) || []),
      json(field(observation, :dependencies) || []),
      json(Model.plain(observation))
    ]
  end

  @doc "Replaces declared dependency keys for one derived record. Dependencies drive recomputation, never deletion."
  def replace_dependencies(repo, screenplay_id, subject_kind, subject_id, dependencies, opts \\ [])
      when is_binary(screenplay_id) and is_binary(subject_kind) and is_binary(subject_id) and
             is_list(dependencies) do
    dependencies = dependencies |> Enum.map(&to_string/1) |> Enum.uniq() |> Enum.sort()
    run_id = Keyword.get(opts, :analysis_run_id)

    transaction(repo, fn ->
      if is_binary(run_id) do
        q(
          repo,
          "DELETE FROM analysis_dependencies WHERE analysis_run_id=$1::uuid AND subject_kind=$2 AND subject_id=$3",
          [run_id, subject_kind, subject_id]
        )
      else
        rollback(repo, :analysis_run_required_for_dependencies)
      end

      Enum.each(dependencies, fn dependency ->
        q(
          repo,
          "INSERT INTO analysis_dependencies(id,screenplay_id,subject_kind,subject_id,dependency_key,analysis_run_id) VALUES($1::uuid,$2::uuid,$3,$4,$5,$6::uuid)",
          [ID.v4(), screenplay_id, subject_kind, subject_id, dependency, run_id]
        )
      end)

      dependencies
    end)
  end

  @doc "Returns derived records whose declared inputs intersect changed dependency keys."
  def affected_records(repo, screenplay_id, changed_dependencies)
      when is_binary(screenplay_id) and is_list(changed_dependencies) do
    keys = changed_dependencies |> Enum.map(&to_string/1) |> Enum.uniq() |> Enum.sort()

    case keys do
      [] ->
        []

      _ ->
        all(
          repo,
          "WITH latest_runs AS (SELECT DISTINCT ON (d.subject_kind,d.subject_id) d.subject_kind,d.subject_id,d.analysis_run_id FROM analysis_dependencies d JOIN analysis_runs r ON r.id=d.analysis_run_id WHERE d.screenplay_id=$1::uuid ORDER BY d.subject_kind,d.subject_id,r.inserted_at DESC,d.analysis_run_id DESC) SELECT DISTINCT d.subject_kind,d.subject_id,d.analysis_run_id FROM analysis_dependencies d JOIN latest_runs l ON l.subject_kind=d.subject_kind AND l.subject_id=d.subject_id AND l.analysis_run_id=d.analysis_run_id WHERE d.screenplay_id=$1::uuid AND d.dependency_key = ANY($2::text[]) ORDER BY d.subject_kind,d.subject_id",
          [screenplay_id, keys]
        )
    end
  end

  defp valid_asset(asset) do
    valid =
      text?(field(asset, :scope_id)) and field(asset, :kind) in @asset_kinds and
        text?(field(asset, :logical_id)) and text?(field(asset, :trust)) and
        is_map(field(asset, :source) || %{}) and is_map(field(asset, :content)) and
        digest?(field(asset, :sha256))

    if valid, do: :ok, else: {:error, :invalid_analysis_asset}
  end

  defp valid_run(run) do
    valid =
      text?(field(run, :screenplay_id)) and text?(field(run, :revision_id)) and
        digest?(field(run, :revision_content_sha256)) and text?(field(run, :playbook)) and
        text?(field(run, :privacy_namespace)) and
        (field(run, :status) || "running") in @run_statuses

    if valid, do: :ok, else: {:error, :invalid_analysis_run}
  end

  defp run_identity(run) do
    %{
      "screenplay_id" => field(run, :screenplay_id),
      "revision_id" => field(run, :revision_id),
      "revision_content_sha256" => field(run, :revision_content_sha256),
      "session_id" => field(run, :session_id),
      "candidate_id" => field(run, :candidate_id),
      "playbook" => field(run, :playbook),
      "playbook_sha256" => field(run, :playbook_sha256),
      "privacy_namespace" => field(run, :privacy_namespace)
    }
  end

  defp valid_cache_results(results, key) do
    valid =
      Enum.with_index(results)
      |> Enum.all?(fn {result, _ordinal} ->
        text?(field(result, :id)) and digest?(field(result, :measurement_spec_sha256)) and
          digest?(field(result, :input_sha256)) and digest?(field(result, :semantic_execution_sha256)) and
          text?(field(result, :output_contract_id)) and digest?(field(result, :output_contract_sha256)) and
          is_map(field(result, :provider_fingerprint)) and
          get_in(Model.plain(result), ["metadata", "cache_key"]) == key
      end)

    if valid, do: :ok, else: {:error, :invalid_analysis_cache_entry}
  end

  defp valid_observations(observations, screenplay_id, revision_id) do
    valid =
      Enum.all?(observations, fn observation ->
        evidence = List.wrap(field(observation, :evidence) || [])
        target = field(observation, :target) || %{}

        text?(field(observation, :id)) and not is_nil(field(observation, :kind)) and
          is_map(target) and field(target, :screenplay_id) == screenplay_id and
          field(target, :revision_id) == revision_id and
          Enum.all?(evidence, &current_evidence?(&1, screenplay_id, revision_id))
      end)

    if valid, do: :ok, else: {:error, :stale_analysis_observation_provenance}
  end

  defp current_evidence?(item, screenplay_id, revision_id) do
    evidence_screenplay = field(item, :screenplay_id)
    evidence_revision = field(item, :revision_id)

    (is_nil(evidence_screenplay) or evidence_screenplay == screenplay_id) and
      (is_nil(evidence_revision) or evidence_revision == revision_id)
  end

  defp secret_free(value) do
    if contains_secret_key?(value), do: {:error, :credential_material_forbidden}, else: :ok
  end

  defp contains_secret_key?(%_{} = value), do: contains_secret_key?(Map.from_struct(value))

  defp contains_secret_key?(value) when is_map(value) do
    Enum.any?(value, fn {key, nested} ->
      String.downcase(to_string(key)) in @forbidden_secret_keys or contains_secret_key?(nested)
    end)
  end

  defp contains_secret_key?(items) when is_list(items), do: Enum.any?(items, &contains_secret_key?/1)
  defp contains_secret_key?(_), do: false

  defp text?(value), do: is_binary(value) and String.trim(value) != ""
  defp digest?(value), do: is_binary(value) and byte_size(value) == 64 and Regex.match?(~r/^[0-9a-f]+$/, value)
  defp field(map, key), do: Map.get(map, key, Map.get(map, to_string(key)))
  defp json(value), do: Jason.encode!(Model.plain(value))

  defp q(repo, sql, params) do
    SQL.query!(
      repo,
      sql |> String.replace("::uuid", "::text::uuid") |> String.replace("::jsonb", "::text::jsonb"),
      params,
      log: false
    )
  end

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
               "screenplay_id",
               "revision_id",
               "session_id",
               "candidate_id",
               "analysis_run_id",
               "parent_id"
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
