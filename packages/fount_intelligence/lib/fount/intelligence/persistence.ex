defmodule Fount.Intelligence.Persistence do
  @moduledoc """
  Intelligence-owned durable analysis shell.

  Pure StoryWorld, Reader, Diagnosis and capability modules remain free of Repo
  access. This shell starts/finishes analysis runs, exposes Observe's durable L2
  cache adapter, persists fresh current-revision observations, and records
  dependency keys for later recomputation.
  """

  alias Fount.Intelligence.Packs
  alias Fount.Intelligence.Persistence.MeasurementCache
  alias Fount.Intelligence.Reporting.WriterPacket
  alias Fount.Observe.DeclarativeLens
  alias Fount.Persistence.Analysis
  alias Fount.Screenplay.Model
  alias Fount.Writing.CanonicalJSON

  defstruct [:repo, :privacy_namespace, :l1_cache]

  defmodule Run do
    @moduledoc false
    defstruct [
      :store,
      :id,
      :screenplay_id,
      :revision_id,
      :revision_content_sha256,
      :session_id,
      :candidate_id,
      :playbook
    ]
  end

  @doc "Creates a caller-owned durable analysis store. No process or provider is started."
  def new(repo, opts \\ []) when is_list(opts) do
    %__MODULE__{
      repo: repo,
      privacy_namespace: Keyword.get(opts, :privacy_namespace),
      l1_cache: Keyword.get(opts, :l1_cache)
    }
  end

  @doc "Starts one logical analysis run and binds its durable cache namespace."
  def begin(%__MODULE__{} = store, model, playbook, attrs \\ %{}) when is_map(attrs) do
    namespace = store.privacy_namespace || "screenplay:" <> model.id
    id = attr(attrs, :id, Fount.ID.v4())

    run = %{
      id: id,
      screenplay_id: model.id,
      revision_id: model.revision.id,
      revision_content_sha256: model.revision.content_hash,
      session_id: attr(attrs, :session_id),
      candidate_id: attr(attrs, :candidate_id),
      playbook: playbook,
      playbook_sha256: attr(attrs, :playbook_sha256),
      status: "running",
      concern: attr(attrs, :concern, %{}),
      intent: attr(attrs, :intent, %{}),
      scope: attr(attrs, :scope, %{}),
      privacy_namespace: namespace,
      preflight: attr(attrs, :preflight, %{}),
      metadata: attr(attrs, :metadata, %{})
    }

    with {:ok, saved} <- Analysis.start_run(store.repo, run) do
      {:ok,
       %Run{
         store: %{store | privacy_namespace: namespace},
         id: saved[:id] || saved["id"] || id,
         screenplay_id: model.id,
         revision_id: model.revision.id,
         revision_content_sha256: model.revision.content_hash,
         session_id: run.session_id,
         candidate_id: run.candidate_id,
         playbook: playbook
       }}
    end
  end

  defp attr(attrs, key, default \\ nil),
    do: Map.get(attrs, to_string(key)) || Map.get(attrs, key) || default

  @doc "Adds the durable L2 adapter without discarding a caller's existing L1 cache."
  def measurement_options(%Run{} = run, opts) when is_list(opts) do
    existing_l1 = Keyword.get(opts, :cache, run.store.l1_cache)

    handle = %{
      repo: run.store.repo,
      privacy_namespace: run.store.privacy_namespace,
      l1: existing_l1
    }

    opts
    |> Keyword.put(:cache, {MeasurementCache, handle})
    |> Keyword.put(:privacy_namespace, run.store.privacy_namespace)
    |> Keyword.put(:cache_policy, :durable)
    |> Keyword.put(:run_id, run.id)
  end

  def measurement_options(nil, opts), do: opts

  @doc "Persists only fresh Observation bindings from an executed Observe batch."
  def record_batch(%Run{} = run, model, batch) do
    observations =
      batch.entries
      |> Enum.flat_map(fn entry -> Map.get(entry, :observations, []) end)

    with :ok <- ensure_durable_results(run, observations),
         {:ok, _} <-
           Analysis.save_observations(
             run.store.repo,
             run.id,
             model.id,
             model.revision.id,
             observations
           ) do
      Enum.each(observations, fn observation ->
        dependencies = dependency_keys(observation.dependencies)

        _ =
          Analysis.replace_dependencies(
            run.store.repo,
            model.id,
            "observation",
            observation.id,
            dependencies,
            analysis_run_id: run.id
          )
      end)

      :ok
    end
  end

  def record_batch(nil, _model, _batch), do: :ok

  @doc "Finishes a writer packet run and returns the same packet with durable run lineage."
  def finish_packet(%Run{} = run, %WriterPacket{} = packet) do
    packet =
      %{packet | provenance: Map.put(packet.provenance, "analysis_run_id", run.id)}

    map = WriterPacket.to_map(packet)

    dependencies =
      packet.evidence
      |> Enum.flat_map(&evidence_dependency_keys/1)
      |> Enum.uniq()
      |> Enum.sort()

    with {:ok, _} <-
           Analysis.finish_run(run.store.repo, run.id, %{
             status: packet.status,
             output_contract_id: packet.output_contract_id,
             output_contract_sha256: packet.output_contract_sha256,
             resource_usage: packet.resource_usage,
             summary:
               Map.take(
                 map,
                 ~w(id playbook concern finding coverage diagnoses uncertainty protected_strengths next_investigations revision_comparison)
               ),
             result: map,
             metadata: %{
               "candidate_is_canon" => false,
               "claim_class" => packet.claim_class,
               "source_revision" => packet.source_revision
             }
           }),
         {:ok, _} <-
           Analysis.replace_dependencies(
             run.store.repo,
             run.screenplay_id,
             "writer_packet",
             packet.id,
             dependencies,
             analysis_run_id: run.id
           ),
         :ok <- persist_diagnosis_dependencies(run, packet, dependencies) do
      {:ok, packet}
    end
  end

  def finish_packet(nil, %WriterPacket{} = packet), do: {:ok, packet}

  @doc "Records a failed run without converting the failure into a screenplay decision."
  def fail(%Run{} = run, reason) do
    Analysis.finish_run(run.store.repo, run.id, %{
      status: "failed",
      summary: %{"reason" => safe_reason(reason)},
      metadata: %{"changes_canon" => false}
    })
  end

  def fail(nil, _reason), do: :ok

  @doc "Deterministic canonical JSON export of one durable analysis run and its audit records."
  def export_run(%__MODULE__{} = store, id) do
    with {:ok, bundle} <- Analysis.audit_bundle(store.repo, id),
         {:ok, json} <- CanonicalJSON.encode(Model.plain(bundle)) do
      {:ok, json <> "\n"}
    end
  end

  @doc "Returns durable provider/resource usage history for longitudinal estimates."
  def usage_history(%__MODULE__{} = store, screenplay_id, playbook, opts \\ []) do
    Analysis.usage_history(store.repo, screenplay_id, playbook, opts)
  end

  @doc "Evicts reusable measurement rows for this privacy namespace only."
  def evict_cache(%__MODULE__{} = store, keep_entries)
      when is_integer(keep_entries) and keep_entries >= 0 do
    case store.privacy_namespace do
      namespace when is_binary(namespace) and namespace != "" ->
        Analysis.evict_cache(store.repo, namespace, keep_entries)

      _ ->
        {:error, :privacy_namespace_required}
    end
  end

  @doc "Persists a validated declarative lens as disabled-by-default data when host policy permits it."
  def save_lens(%__MODULE__{} = store, screenplay_id, declaration, opts \\ []) do
    with :ok <- project_assets_allowed(opts),
         {:ok, asset} <- DeclarativeLens.validate(declaration) do
      persist_asset(store, screenplay_id, "lens", asset, opts)
    end
  end

  @doc "Persists a validated project/studio genre pack as disabled-by-default data when host policy permits it."
  def save_genre_pack(%__MODULE__{} = store, screenplay_id, pack, opts \\ []) do
    with :ok <- project_assets_allowed(opts),
         {:ok, asset} <- Packs.validate(pack, opts) do
      persist_asset(store, screenplay_id, "genre_pack", asset, opts)
    end
  end

  @doc "Persists a data-only calibration or playbook asset when host policy permits it."
  def save_data_asset(store, screenplay_id, kind, logical_id, content, opts \\ [])

  def save_data_asset(%__MODULE__{} = store, screenplay_id, kind, logical_id, content, opts)
      when kind in ["calibration", "playbook"] and is_binary(logical_id) and is_map(content) do
    source = Keyword.get(opts, :source)

    with :ok <- project_assets_allowed(opts),
         :ok <- safe_data_asset(content),
         {:ok, _json} <- CanonicalJSON.encode(content),
         :ok <- require_asset_source(source) do
      scope =
        Keyword.get(opts, :scope_id, store.privacy_namespace || "screenplay:" <> screenplay_id)

      Analysis.save_asset(store.repo, %{
        screenplay_id: screenplay_id,
        scope_id: scope,
        kind: kind,
        logical_id: logical_id,
        trust: Keyword.get(opts, :trust, "project"),
        source: source,
        content: content,
        sha256: CanonicalJSON.hash(content),
        parent_id: Keyword.get(opts, :parent_id),
        enabled: Keyword.get(opts, :enabled, false)
      })
    end
  end

  def save_data_asset(%__MODULE__{}, _screenplay_id, _kind, _logical_id, _content, _opts),
    do: {:error, :invalid_analysis_asset}

  @doc "Explicitly enables or disables a persisted asset; saving an asset never enables it implicitly."
  def set_asset_enabled(%__MODULE__{} = store, asset_id, enabled) when is_boolean(enabled),
    do: Analysis.set_asset_enabled(store.repo, asset_id, enabled)

  defp persist_asset(store, screenplay_id, kind, asset, opts) do
    scope =
      Keyword.get(opts, :scope_id, store.privacy_namespace || "screenplay:" <> screenplay_id)

    content = Map.delete(asset, "sha256")

    Analysis.save_asset(store.repo, %{
      screenplay_id: screenplay_id,
      scope_id: scope,
      kind: kind,
      logical_id: asset["id"],
      trust: asset["trust"],
      source: asset["source"],
      content: content,
      sha256: CanonicalJSON.hash(content),
      parent_id: Keyword.get(opts, :parent_id),
      enabled: Keyword.get(opts, :enabled, false)
    })
  end

  defp ensure_durable_results(run, observations) do
    observations
    |> Enum.group_by(fn observation -> get_in(observation.result.metadata, ["cache_key"]) end)
    |> Enum.reduce_while(:ok, fn
      {key, grouped}, :ok when is_binary(key) and key != "" ->
        results = Enum.map(grouped, & &1.result)

        case Analysis.cache_put(run.store.repo, run.store.privacy_namespace, key, results) do
          {:ok, :ok} -> {:cont, :ok}
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
          _ -> {:halt, {:error, :durable_cache_write_failed}}
        end

      {_key, _grouped}, :ok ->
        {:halt, {:error, :durable_cache_identity_missing}}
    end)
  end

  defp persist_diagnosis_dependencies(run, packet, default_dependencies) do
    Enum.reduce_while(packet.diagnoses, :ok, fn diagnosis, :ok ->
      id = diagnosis["id"] || diagnosis[:id]

      dependencies =
        diagnosis
        |> diagnosis_dependency_keys()
        |> Kernel.++(default_dependencies)
        |> Enum.uniq()
        |> Enum.sort()

      persist_diagnosis_dependency(run, id, dependencies)
    end)
  end

  defp persist_diagnosis_dependency(_run, id, _dependencies) when not is_binary(id) or id == "",
    do: {:cont, :ok}

  defp persist_diagnosis_dependency(run, id, dependencies) do
    case Analysis.replace_dependencies(
           run.store.repo,
           run.screenplay_id,
           "diagnosis",
           id,
           dependencies,
           analysis_run_id: run.id
         ) do
      {:ok, _} -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp diagnosis_dependency_keys(diagnosis) when is_map(diagnosis) do
    [diagnosis["support"], diagnosis["counterevidence"]]
    |> Enum.flat_map(&List.wrap/1)
    |> Enum.flat_map(&evidence_dependency_keys/1)
    |> Kernel.++(
      diagnosis
      |> get_in(["provenance", "observation_ids"])
      |> List.wrap()
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&("observation:" <> &1))
    )
  end

  defp diagnosis_dependency_keys(_), do: []

  defp project_assets_allowed(opts) do
    if Keyword.get(opts, :allow_project_assets, false),
      do: :ok,
      else: {:error, :project_assets_disabled}
  end

  defp require_asset_source(source) when is_map(source) and map_size(source) > 0, do: :ok
  defp require_asset_source(_source), do: {:error, :analysis_asset_source_required}

  @forbidden_asset_keys ~w(module function mfa shell command path endpoint database callback decoder tool adapter)

  defp safe_data_asset(value) do
    if unsafe_asset_value?(value),
      do: {:error, :executable_analysis_asset_forbidden},
      else: :ok
  end

  defp unsafe_asset_value?(value) when is_map(value) do
    Enum.any?(value, fn {key, nested} ->
      String.downcase(to_string(key)) in @forbidden_asset_keys or unsafe_asset_value?(nested)
    end)
  end

  defp unsafe_asset_value?(value) when is_list(value),
    do: Enum.any?(value, &unsafe_asset_value?/1)

  defp unsafe_asset_value?(_), do: false

  @doc "Canonical dependency keys shared by persistence and recomputation planning."
  def dependency_keys(dependencies) when is_list(dependencies) do
    dependencies
    |> Enum.flat_map(&dependency_keys_for/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def dependency_keys(_), do: []

  defp dependency_keys_for(dependency) do
    target = dependency["target"] || dependency[:target] || %{}
    kind = target["kind"] || target[:kind]
    id = target["id"] || target[:id]
    target_key = if is_binary(kind) and is_binary(id), do: ["target:#{kind}:#{id}"], else: []

    [
      "dependency:" <> CanonicalJSON.hash(Model.plain(dependency))
      | target_key ++ evidence_key(dependency)
    ]
  end

  defp evidence_key(dependency) do
    case {dependency["kind"] || dependency[:kind], dependency["id"] || dependency[:id]} do
      {kind, id} when kind in ["evidence", :evidence] and is_binary(id) -> ["evidence:#{id}"]
      _ -> []
    end
  end

  defp evidence_dependency_keys(evidence) when is_map(evidence) do
    target = evidence["target"] || evidence[:target] || %{}
    kind = target["kind"] || target[:kind]
    id = target["id"] || target[:id]

    evidence_id =
      evidence["evidence_id"] || evidence[:evidence_id] || evidence["id"] || evidence[:id]

    []
    |> maybe_key(is_binary(kind) and is_binary(id), "target:#{kind}:#{id}")
    |> maybe_key(is_binary(evidence_id), "evidence:#{evidence_id}")
  end

  defp evidence_dependency_keys(_), do: []

  defp maybe_key(keys, true, key), do: [key | keys]
  defp maybe_key(keys, false, _key), do: keys

  defp safe_reason(reason) when is_atom(reason), do: to_string(reason)
  defp safe_reason({reason, _}) when is_atom(reason), do: to_string(reason)
  defp safe_reason(_), do: "analysis_failed"
end
