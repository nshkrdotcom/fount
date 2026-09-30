defmodule FountWeb.AnalysisDashboard do
  @moduledoc """
  Owner-scoped, read-only projection of already persisted Run and Intelligence evidence.

  The dashboard never starts Workshop, Inference, Observe, or provider work. It reads the
  authoritative Run ledger plus durable analysis rows and projects explicit unavailable,
  stale, and incomparable states for the Phoenix UI.
  """

  alias Ecto.Adapters.SQL
  alias Fount.Writing.CanonicalJSON

  @history_limit 80
  @graph_node_limit 48
  @graph_edge_limit 96
  @numeric_delta_limit 48

  @uuid_text_columns ~w(id screenplay_id revision_id session_id candidate_id analysis_run_id)

  def load(repo, owner_id, run_id, params \\ %{})
      when is_binary(owner_id) and is_binary(run_id) and is_map(params) do
    with {:ok, access} <- FountWeb.Store.run_access(repo, owner_id, run_id),
         {:ok, context} <- FountWeb.Actors.owner_context(owner_id, access["screenplay_id"]),
         {:ok, run} <- FountRun.get_run(repo, run_id, context),
         {:ok, progress} <- FountRun.progress(repo, run_id, context),
         true <- run["screenplay_id"] == access["screenplay_id"] do
      {:ok, project(repo, access, run, progress, params)}
    else
      false -> {:error, :run_screenplay_mismatch}
      {:error, _} = error -> error
    end
  end

  @doc "Returns the exact candidate/base/packet binding used by the review surface."
  def review_binding(repo, run, progress) when is_map(run) and is_map(progress) do
    base_revision_id = get_in(run, ["plan", "base_revision_id"])
    candidate_id = selected_candidate_id(run, progress)

    candidate = stored_candidate(repo, candidate_id)
    revision_packet = candidate |> field("provenance") |> field("revision_intelligence")

    %{
      "base_revision_id" => base_revision_id,
      "candidate_id" => candidate_id,
      "candidate_revision_id" => field(candidate, "result_revision_id"),
      "candidate_status" => field(candidate, "status"),
      "check_set_fingerprint" => field(candidate, "check_set_fingerprint"),
      "packet_id" => field(revision_packet, "id"),
      "analysis_run_id" => revision_packet |> field("provenance") |> field("analysis_run_id"),
      "packet_source_revision_id" => field(revision_packet, "source_revision"),
      "packet_status" => field(revision_packet, "status"),
      "freshness" => review_freshness(candidate, revision_packet)
    }
  end

  defp stored_candidate(repo, id) when is_binary(id) do
    case Fount.Persistence.candidate(repo, id) do
      {:ok, stored} -> stored
      _ -> nil
    end
  end

  defp stored_candidate(_repo, _id), do: nil
  defp field(nil, _key), do: nil
  defp field(map, key), do: map[key]

  @doc "Returns the bounded persisted identities that are reachable from this Run."
  def lineage(progress, run) when is_map(progress) and is_map(run) do
    analysis = List.wrap(progress["analysis"])

    packets =
      analysis
      |> Enum.flat_map(fn entry -> [entry["writer"], entry["revision"]] end)
      |> Enum.filter(&is_map/1)

    steps = List.wrap(progress["steps"])

    %{
      analysis_run_ids:
        packets
        |> Enum.map(& &1["analysis_run_id"])
        |> compact_ids(),
      session_ids:
        (Enum.map(analysis, & &1["session_id"]) ++
           Enum.flat_map(steps, fn step ->
             [step["session_id"], get_in(step, ["result", "session_id"])]
           end))
        |> compact_ids(),
      candidate_ids:
        ([run["selected_candidate_id"]] ++
           Enum.map(analysis, & &1["candidate_id"]) ++
           Enum.flat_map(steps, fn step ->
             result = step["result"] || %{}

             [step["input_candidate_id"], step["output_candidate_id"], result["candidate_id"]] ++
               List.wrap(result["candidate_ids"])
           end) ++
           Enum.map(List.wrap(progress["decisions"]), & &1["candidate_id"]) ++
           Enum.map(List.wrap(progress["approval_attempts"]), & &1["candidate_id"]) ++
           Enum.map(List.wrap(progress["deliveries"]), & &1["candidate_id"]))
        |> compact_ids(),
      revision_ids:
        ([get_in(run, ["plan", "base_revision_id"])] ++
           Enum.map(analysis, & &1["revision_id"]) ++
           Enum.map(packets, & &1["source_revision_id"]) ++
           Enum.flat_map(steps, fn step ->
             result = step["result"] || %{}
             [step["input_revision_id"], step["output_revision_id"], result["revision_id"]]
           end) ++
           Enum.map(List.wrap(progress["decisions"]), & &1["base_revision_id"]) ++
           Enum.map(List.wrap(progress["approval_attempts"]), & &1["base_revision_id"]) ++
           Enum.map(List.wrap(progress["deliveries"]), & &1["accepted_revision_id"]))
        |> compact_ids()
    }
  end

  @doc "Pure comparison helper used by focused tests and the read-only comparison UI."
  def compare_runs(left, right) when is_map(left) and is_map(right) do
    compatibility = compatibility(left, right)

    if compatibility.reasons == [] do
      %{
        state: :comparable,
        reasons: [],
        left_id: left["id"],
        right_id: right["id"],
        deltas: numeric_deltas(left["result"] || %{}, right["result"] || %{}),
        uncertainty: comparison_uncertainty(left, right)
      }
    else
      %{
        state: :incomparable,
        reasons: compatibility.reasons,
        left_id: left["id"],
        right_id: right["id"],
        deltas: [],
        uncertainty: comparison_uncertainty(left, right)
      }
    end
  end

  @doc "Pure bounded graph projection from persisted observation payloads."
  def graph_from_observations(observations, opts \\ []) when is_list(observations) do
    node_limit = Keyword.get(opts, :node_limit, @graph_node_limit)
    edge_limit = Keyword.get(opts, :edge_limit, @graph_edge_limit)
    records = observation_records(observations)
    evidence = evidence_registry(observations)

    {nodes, edges, events} = graph_records(records, evidence)
    nodes = Enum.uniq_by(nodes, & &1.id)
    edges = Enum.uniq_by(edges, &{&1.from, &1.to, &1.kind, &1.record_id})

    visible_nodes = Enum.take(nodes, node_limit)
    visible_ids = MapSet.new(Enum.map(visible_nodes, & &1.id))

    visible_edges =
      edges
      |> Enum.filter(
        &(MapSet.member?(visible_ids, &1.from) and MapSet.member?(visible_ids, &1.to))
      )
      |> Enum.take(edge_limit)

    %{
      nodes: position_nodes(visible_nodes),
      edges: visible_edges,
      events: events,
      total_nodes: length(nodes),
      total_edges: length(edges),
      node_limit: node_limit,
      edge_limit: edge_limit,
      truncated: length(nodes) > node_limit or length(edges) > edge_limit,
      explanation:
        "Nodes and links come only from persisted story-world records and recorded references. Only an explicitly typed causal_relation renders a causal edge; causality is never inferred from order, proximity, or prose."
    }
  end

  defp project(repo, access, run, progress, params) do
    review = review_binding(repo, run, progress)

    run_lineage =
      progress
      |> lineage(run)
      |> augment_lineage(review)

    history = analysis_runs(repo, access["screenplay_id"], run_lineage)

    fingerprints =
      observation_fingerprints(repo, access["screenplay_id"], Enum.map(history, & &1["id"]))

    history =
      Enum.map(history, fn row ->
        row
        |> Map.put("_provider_fingerprints", fingerprints[row["id"]] || [])
        |> Map.put("_lineage_kind", lineage_kind(row, run_lineage))
      end)

    selected = select_run(history, params["packet"], review["analysis_run_id"])
    observations = if selected, do: observations(repo, selected["id"]), else: []
    graph = graph_from_observations(observations)
    selected_view = packet_view(selected, review, observations, run_lineage)
    comparison = comparison(history, params["left"], params["right"])

    %{
      access: access,
      run: run,
      progress: progress,
      lineage: run_lineage,
      review: review,
      history: Enum.map(history, &history_row(&1, review, run_lineage)),
      selected: selected_view,
      graph: graph,
      usage: usage_summary(progress, run),
      checks: check_categories(progress),
      comparison: comparison,
      target: target_context(params, selected_view),
      constraints: %{
        history_limit: @history_limit,
        graph_node_limit: @graph_node_limit,
        graph_edge_limit: @graph_edge_limit
      }
    }
  end

  defp analysis_runs(repo, screenplay_id, lineage) do
    sql = """
    SELECT id::text,screenplay_id::text,revision_id::text,revision_content_sha256,
           session_id::text,candidate_id::text,playbook,playbook_sha256,status,concern,intent,scope,
           output_contract_id,output_contract_sha256,preflight,resource_usage,summary,result,metadata,
           started_at,finished_at,inserted_at
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

    query_rows(repo, sql, [
      screenplay_id,
      lineage.analysis_run_ids,
      lineage.session_ids,
      lineage.candidate_ids,
      lineage.revision_ids,
      @history_limit
    ])
  end

  defp observation_fingerprints(_repo, _screenplay_id, []), do: %{}

  defp observation_fingerprints(repo, screenplay_id, analysis_run_ids) do
    sql = """
    SELECT analysis_run_id::text,
           COALESCE(jsonb_agg(DISTINCT payload->'result'->'provider_fingerprint')
             FILTER (WHERE payload->'result'->'provider_fingerprint' IS NOT NULL), '[]'::jsonb) AS fingerprints
    FROM analysis_observations
    WHERE screenplay_id=$1::text::uuid AND analysis_run_id::text = ANY($2::text[])
    GROUP BY analysis_run_id
    """

    query_rows(repo, sql, [screenplay_id, analysis_run_ids])
    |> Map.new(&{&1["analysis_run_id"], &1["fingerprints"] || []})
  end

  defp observations(repo, analysis_run_id) do
    sql = """
    SELECT id,analysis_run_id::text,screenplay_id::text,revision_id::text,request_id,result_id,kind,
           target,evidence,dependencies,payload,inserted_at
    FROM analysis_observations
    WHERE analysis_run_id=$1::text::uuid
    ORDER BY inserted_at,id
    """

    query_rows(repo, sql, [analysis_run_id])
  end

  defp select_run([], _requested, _fallback), do: nil

  defp select_run(history, requested, fallback) do
    case requested do
      id when is_binary(id) and id != "" -> Enum.find(history, &(&1["id"] == id))
      _ -> Enum.find(history, &(&1["id"] == fallback)) || List.first(history)
    end
  end

  defp packet_view(nil, _review, _observations, _lineage) do
    %{
      state: "not_run",
      stored_status: nil,
      reason: "No persisted analysis packet is available for this owner-authorized screenplay.",
      run: nil,
      packet: nil,
      observations: [],
      evidence: [],
      diagnoses: [],
      uncertainty: [],
      limitations: [],
      missing_evidence: [],
      protected_strengths: [],
      next_investigations: []
    }
  end

  defp packet_view(row, review, observations, lineage) do
    packet = row["result"] || %{}
    stale = stale?(row, review)

    %{
      state: if(stale, do: "stale", else: packet_status(row)),
      stored_status: normalize_status(row["status"]),
      reason: status_reason(row, packet, stale),
      run: history_row(row, review, lineage),
      packet: packet,
      observations: observations,
      evidence: List.wrap(packet["evidence"]),
      diagnoses: List.wrap(packet["diagnoses"]),
      uncertainty: List.wrap(packet["uncertainty"]),
      limitations: List.wrap(packet["limitations"]),
      missing_evidence: List.wrap(packet["missing_evidence"]),
      protected_strengths: List.wrap(packet["protected_strengths"]),
      next_investigations: List.wrap(packet["next_investigations"])
    }
  end

  defp history_row(row, review, lineage) do
    %{
      "id" => row["id"],
      "revision_id" => row["revision_id"],
      "candidate_id" => row["candidate_id"],
      "session_id" => row["session_id"],
      "playbook" => row["playbook"],
      "playbook_sha256" => row["playbook_sha256"],
      "status" => normalize_status(row["status"]),
      "display_status" => if(stale?(row, review), do: "stale", else: packet_status(row)),
      "scope" => row["scope"] || %{},
      "output_contract_id" => row["output_contract_id"],
      "output_contract_sha256" => row["output_contract_sha256"],
      "measurement_identity" => measurement_identity(row),
      "provider_fingerprint" => provider_fingerprint(row),
      "evidence_identity" => evidence_identity(row),
      "lineage_kind" => row["_lineage_kind"] || lineage_kind(row, lineage),
      "resource_usage" => row["resource_usage"] || %{},
      "started_at" => row["started_at"],
      "finished_at" => row["finished_at"]
    }
  end

  defp stale?(row, review) do
    expected = review["candidate_revision_id"] || review["base_revision_id"]
    is_binary(expected) and row["revision_id"] != expected
  end

  defp review_freshness(nil, _packet), do: "no_candidate"
  defp review_freshness(_candidate, nil), do: "missing"

  defp review_freshness(candidate, packet) do
    if packet["source_revision"] == candidate["result_revision_id"], do: "current", else: "stale"
  end

  defp packet_status(%{"status" => "failed"}), do: "failed"

  defp packet_status(row) do
    if row["result"] in [nil, %{}], do: "not_run", else: normalize_status(row["status"])
  end

  defp normalize_status(status) when status in ["complete", "partial", "failed"], do: status
  defp normalize_status("running"), do: "not_run"
  defp normalize_status(_), do: "not_run"

  defp status_reason(_row, _packet, true),
    do: "This packet is bound to a different persisted revision than the current review target."

  defp status_reason(%{"status" => "failed"}, packet, false),
    do:
      packet["reason"] || get_in(packet, ["summary", "reason"]) ||
        "The stored analysis run failed."

  defp status_reason(%{"status" => "partial"}, packet, false) do
    case List.wrap(packet["errors"]) do
      [] -> "The stored packet is partial; inspect coverage, uncertainty, and missing evidence."
      errors -> "The stored packet is partial with #{length(errors)} recorded error(s)."
    end
  end

  defp status_reason(%{"status" => "complete"}, _packet, false),
    do:
      "The stored packet completed for its recorded revision. Completeness is not screenplay quality."

  defp status_reason(_, _, false), do: "No completed stored analysis packet is available."

  defp check_categories(progress) do
    checks = latest_checks(progress)

    %{
      required_deterministic:
        Enum.filter(checks, &(&1["severity"] == "required" and &1["source"] == "run")),
      workshop_application:
        Enum.filter(checks, fn check ->
          check["severity"] == "required" and check["source"] != "run"
        end),
      semantic_advisory: Enum.filter(checks, &(&1["severity"] == "advisory")),
      other:
        Enum.reject(checks, fn check ->
          (check["severity"] == "required" and check["source"] == "run") or
            (check["severity"] == "required" and check["source"] != "run") or
            check["severity"] == "advisory"
        end)
    }
  end

  defp latest_checks(progress) do
    progress
    |> Map.get("steps", [])
    |> List.wrap()
    |> Enum.reverse()
    |> Enum.find_value([], fn step ->
      if step["stage"] == "check", do: get_in(step, ["result", "checks"]) || [], else: nil
    end)
  end

  defp usage_summary(progress, run) do
    rows = List.wrap(progress["usage"])

    totals =
      Enum.reduce(rows, %{}, fn row, acc ->
        resource = row["resource"] || "unknown"
        current = Map.get(acc, resource, empty_usage(resource))
        Map.put(acc, resource, add_usage(current, row))
      end)

    %{
      rows: rows,
      totals: totals |> Map.values() |> Enum.sort_by(& &1.resource),
      authoritative_resources: progress["resources"] || %{},
      policy_limits: get_in(run, ["policy", "policy", "limits"]) || %{},
      note:
        "Ledger rows show this Run's persisted reservations and settlements. Backend resource status is the authoritative recursive Run-lineage ceiling/consumption view. measurement_states are semantic states, not HTTP request counts; replay/cache identity does not create synthetic usage."
    }
  end

  defp empty_usage(resource) do
    %{
      resource: resource,
      reserved: 0,
      consumed: 0,
      outstanding_reserved: 0,
      unknown_rows: 0,
      unknown_cost_rows: 0,
      reserved_cost_microunits: 0,
      consumed_cost_microunits: 0,
      currencies: []
    }
  end

  defp add_usage(total, row) do
    reserved = integer_or_zero(row["reserved_quantity"])
    settled = row["settled_quantity"]
    released = row["reconciliation_state"] == "released"
    known = known_settlement?(row) and not released
    settled_value = if known, do: settled, else: 0
    reservation_value = if released, do: 0, else: reserved

    total
    |> Map.update!(:reserved, &(&1 + reservation_value))
    |> Map.update!(:consumed, &(&1 + settled_value))
    |> Map.update!(:outstanding_reserved, fn value ->
      value + open_reservation(row)
    end)
    |> Map.update!(:unknown_rows, &(&1 + if(known or released, do: 0, else: 1)))
    |> add_cost_usage(row, released)
    |> add_currency(row["currency"])
  end

  defp add_cost_usage(total, row, released) do
    known_cost = known_cost?(row) and not released

    total
    |> Map.update!(
      :reserved_cost_microunits,
      &(&1 + if(released, do: 0, else: integer_or_zero(row["reserved_cost_microunits"])))
    )
    |> Map.update!(:unknown_cost_rows, &(&1 + if(known_cost or released, do: 0, else: 1)))
    |> Map.update!(:consumed_cost_microunits, fn value ->
      value + if(known_cost, do: row["settled_cost_microunits"], else: 0)
    end)
  end

  defp open_reservation(%{"reconciliation_state" => "reserved"} = row),
    do: integer_or_zero(row["reserved_quantity"])

  defp open_reservation(_), do: 0

  defp known_cost?(row),
    do: is_integer(row["settled_cost_microunits"]) and nonempty_identity?(row["currency"])

  defp known_settlement?(row),
    do:
      row["reconciliation_state"] == "settled" and row["knowledge_state"] == "known" and
        is_integer(row["settled_quantity"])

  defp add_currency(total, nil), do: total

  defp add_currency(total, currency) do
    Map.update!(total, :currencies, fn currencies ->
      [currency | currencies] |> Enum.uniq() |> Enum.sort()
    end)
  end

  defp integer_or_zero(value) when is_integer(value), do: value
  defp integer_or_zero(_), do: 0

  defp comparison(_history, nil, nil),
    do: %{state: :unselected, reasons: [], deltas: [], uncertainty: %{left: [], right: []}}

  defp comparison(history, left_id, right_id) do
    left = Enum.find(history, &(&1["id"] == left_id))
    right = Enum.find(history, &(&1["id"] == right_id))

    cond do
      is_nil(left) or is_nil(right) ->
        %{
          state: :unavailable,
          reasons: ["Choose two saved analysis runs from this Run lineage."],
          deltas: [],
          uncertainty: %{left: [], right: []}
        }

      left["id"] == right["id"] ->
        %{
          state: :incomparable,
          reasons: ["Choose two distinct saved analysis runs."],
          deltas: [],
          uncertainty: %{left: [], right: []}
        }

      true ->
        compare_runs(left, right)
    end
  end

  defp compatibility(left, right) do
    reasons =
      []
      |> mismatch(
        left["output_contract_id"],
        right["output_contract_id"],
        "output contract differs"
      )
      |> mismatch(
        left["output_contract_sha256"],
        right["output_contract_sha256"],
        "output contract definition differs"
      )
      |> mismatch(
        scope_identity(left),
        scope_identity(right),
        "analysis scope differs"
      )
      |> mismatch(
        measurement_identity(left),
        measurement_identity(right),
        "measurement definition differs or is unavailable"
      )
      |> mismatch(
        provider_fingerprint(left),
        provider_fingerprint(right),
        "provider/model fingerprint differs or is unavailable"
      )
      |> mismatch(
        evidence_identity(left),
        evidence_identity(right),
        "evidence identity differs or is unavailable"
      )

    %{reasons: Enum.reverse(reasons)}
  end

  defp scope_identity(%{"scope" => scope}) when is_map(scope) and map_size(scope) > 0,
    do: CanonicalJSON.hash(scope)

  defp scope_identity(_), do: nil

  defp mismatch(reasons, nil, _right, message), do: [message | reasons]
  defp mismatch(reasons, _left, nil, message), do: [message | reasons]
  defp mismatch(reasons, value, value, _message), do: reasons
  defp mismatch(reasons, _left, _right, message), do: [message | reasons]

  defp measurement_identity(row) do
    packet = row["result"] || %{}
    provenance = packet["provenance"] || %{}

    definition = %{
      "measurement_spec_sha256" => provenance["measurement_spec_sha256"],
      "base_measurement_spec_sha256" => provenance["base_measurement_spec_sha256"],
      "contextual_measurement_spec_sha256" => provenance["contextual_measurement_spec_sha256"]
    }

    if Enum.any?(definition, fn {_key, value} -> not is_nil(value) end),
      do: CanonicalJSON.hash(definition),
      else: nil
  end

  defp provider_fingerprint(row) do
    values = row["_provider_fingerprints"] || []

    if values != [] and Enum.all?(values, &valid_provider_identity?/1),
      do: CanonicalJSON.hash(Enum.sort_by(values, &CanonicalJSON.hash/1)),
      else: nil
  end

  defp valid_provider_identity?(value) when is_map(value),
    do: nonempty_identity?(value["provider"]) and nonempty_identity?(value["model"])

  defp valid_provider_identity?(_), do: false
  defp nonempty_identity?(value), do: is_binary(value) and String.trim(value) != ""

  defp evidence_identity(row) do
    evidence = get_in(row, ["result", "evidence"]) || []

    identities =
      Enum.map(evidence, fn item ->
        %{
          "id" => item["evidence_id"] || item["id"],
          "target" => item["target"],
          "revision_id" => item["revision_id"] || get_in(item, ["target", "revision_id"]),
          "excerpt_sha256" => item["excerpt_sha256"]
        }
      end)

    if identities != [] and Enum.all?(identities, &valid_evidence_identity?/1),
      do: CanonicalJSON.hash(identities),
      else: nil
  end

  defp valid_evidence_identity?(identity) do
    nonempty_identity?(identity["id"]) and nonempty_identity?(identity["revision_id"]) and
      is_map(identity["target"]) and
      nonempty_identity?(identity["target"]["id"]) and
      nonempty_identity?(identity["excerpt_sha256"])
  end

  defp numeric_deltas(left, right) do
    flatten_numbers(left)
    |> Map.take(Map.keys(flatten_numbers(right)))
    |> Enum.flat_map(fn {path, before} ->
      after_value = flatten_numbers(right)[path]

      if is_number(before) and is_number(after_value) do
        [%{path: path, before: before, after: after_value, delta: after_value - before}]
      else
        []
      end
    end)
    |> Enum.sort_by(& &1.path)
    |> Enum.take(@numeric_delta_limit)
  end

  defp flatten_numbers(value), do: flatten_numbers(value, "", %{})

  defp flatten_numbers(map, prefix, acc) when is_map(map) do
    Enum.reduce(map, acc, fn {key, value}, current ->
      path = if prefix == "", do: to_string(key), else: prefix <> "." <> to_string(key)
      flatten_numbers(value, path, current)
    end)
  end

  defp flatten_numbers(list, prefix, acc) when is_list(list) do
    Enum.with_index(list)
    |> Enum.reduce(acc, fn {value, index}, current ->
      flatten_numbers(value, prefix <> "[#{index}]", current)
    end)
  end

  defp flatten_numbers(value, prefix, acc) when is_number(value), do: Map.put(acc, prefix, value)
  defp flatten_numbers(_value, _prefix, acc), do: acc

  defp observation_records(observations) do
    observations
    |> Enum.with_index()
    |> Enum.flat_map(fn {observation, observation_index} ->
      payload = observation["payload"] || %{}

      records =
        List.wrap(get_in(payload, ["metadata", "story_world_records"])) ++
          List.wrap(get_in(payload, ["result", "value", "story_world_records"]))

      records
      |> Enum.with_index()
      |> Enum.map(fn {record, record_index} ->
        %{
          record: record,
          observation_id: observation["id"],
          observation_index: observation_index,
          record_index: record_index,
          revision_id: observation["revision_id"]
        }
      end)
    end)
  end

  defp evidence_registry(observations) do
    observations
    |> Enum.flat_map(&List.wrap(&1["evidence"]))
    |> Enum.reduce(%{}, fn item, acc ->
      id = item["evidence_id"] || item["id"]
      if is_binary(id), do: Map.put(acc, id, item), else: acc
    end)
  end

  defp graph_records(records, evidence) do
    Enum.reduce(records, {[], [], []}, fn wrapped, {nodes, edges, events} ->
      record = wrapped.record
      kind = normalized_record_kind(record)
      id = record["id"] || "record:#{wrapped.observation_index}:#{wrapped.record_index}"
      label = record["label"] || record["name"] || record["claim"] || record["description"] || id
      inline_evidence = List.wrap(record["evidence"])

      evidence_ids =
        (List.wrap(record["evidence_ids"]) ++
           Enum.map(inline_evidence, &(&1["evidence_id"] || &1["id"])))
        |> compact_ids()

      target =
        first_target(evidence_ids, evidence) || Enum.find_value(inline_evidence, & &1["target"])

      provenance = %{
        observation_id: wrapped.observation_id,
        revision_id: wrapped.revision_id,
        evidence_ids: evidence_ids
      }

      record_node =
        provenance
        |> Map.merge(%{
          id: "record:" <> id,
          label: label,
          kind: graph_kind(kind),
          target: target,
          record_id: id
        })

      subjects =
        (List.wrap(record["subjects"]) ++ List.wrap(record["subject"]))
        |> Enum.filter(&is_binary/1)
        |> Enum.uniq()

      subject_nodes =
        Enum.map(subjects, fn subject ->
          provenance
          |> Map.merge(%{
            id: "subject:" <> subject,
            label: subject,
            kind: "entity",
            target: target,
            record_id: id
          })
        end)

      subject_edges =
        Enum.map(subjects, fn subject ->
          %{
            from: "subject:" <> subject,
            to: record_node.id,
            kind: "recorded_subject",
            label: "recorded subject",
            record_id: id,
            observation_id: wrapped.observation_id,
            revision_id: wrapped.revision_id,
            evidence_ids: evidence_ids
          }
        end)

      {relation_nodes, relation_edges} = explicit_relation(kind, record, id, provenance)

      event_rows =
        if graph_kind(kind) == "event" do
          [
            %{
              id: id,
              label: label,
              order: length(events) + 1,
              revision_id: wrapped.revision_id,
              observation_id: wrapped.observation_id,
              evidence_ids: evidence_ids,
              target: target,
              uncertainty: record["uncertainty"]
            }
          ]
        else
          []
        end

      {[record_node | subject_nodes ++ relation_nodes] ++ nodes,
       subject_edges ++ relation_edges ++ edges, events ++ event_rows}
    end)
    |> then(fn {nodes, edges, events} -> {Enum.reverse(nodes), Enum.reverse(edges), events} end)
  end

  defp explicit_relation(
         "causal_relation",
         %{"from" => from, "to" => to} = record,
         record_id,
         provenance
       )
       when is_binary(from) and is_binary(to) do
    from_id = "reference:" <> from
    to_id = "reference:" <> to

    nodes = [
      Map.merge(provenance, %{
        id: from_id,
        label: from,
        kind: "event",
        target: nil,
        record_id: record_id
      }),
      Map.merge(provenance, %{
        id: to_id,
        label: to,
        kind: "event",
        target: nil,
        record_id: record_id
      })
    ]

    edges = [
      Map.merge(provenance, %{
        from: from_id,
        to: to_id,
        kind: "recorded_causal_relation",
        label: record["causal_type"] || "recorded causal relation",
        record_id: record_id
      })
    ]

    {nodes, edges}
  end

  defp explicit_relation(_kind, _record, _record_id, _provenance), do: {[], []}

  defp normalized_record_kind(record) do
    record["record_type"] || record["type"] || record["kind"] || "record"
  end

  defp graph_kind(kind) when kind in ["event", "events"], do: "event"
  defp graph_kind(kind) when kind in ["entity"], do: "entity"

  defp graph_kind(kind) when kind in ["relationships", "relation", "causal_relation"],
    do: "relation"

  defp graph_kind(_), do: "record"

  defp first_target(evidence_ids, registry) do
    Enum.find_value(evidence_ids, fn id -> get_in(registry, [id, "target"]) end)
  end

  defp position_nodes(nodes) do
    lanes = %{"entity" => 0, "relation" => 1, "record" => 1, "event" => 2}

    nodes
    |> Enum.group_by(&Map.get(lanes, &1.kind, 1))
    |> Enum.flat_map(fn {lane, lane_nodes} ->
      Enum.with_index(lane_nodes)
      |> Enum.map(fn {node, index} ->
        node
        |> Map.put(:x, 120 + lane * 300)
        |> Map.put(:y, 54 + index * 70)
      end)
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp target_context(params, selected) do
    target_id = params["target"]

    evidence =
      selected.evidence
      |> Enum.find(fn item ->
        get_in(item, ["target", "id"]) == target_id or
          (item["evidence_id"] || item["id"]) == target_id
      end)

    %{
      id: target_id,
      evidence: evidence,
      revision_id:
        evidence && (evidence["revision_id"] || get_in(evidence, ["target", "revision_id"])),
      target: evidence && evidence["target"],
      unresolved: is_binary(target_id) and is_nil(evidence)
    }
  end

  defp comparison_uncertainty(left, right) do
    %{
      left: List.wrap(get_in(left, ["result", "uncertainty"])),
      right: List.wrap(get_in(right, ["result", "uncertainty"]))
    }
  end

  defp augment_lineage(lineage, review) do
    lineage
    |> Map.update!(:analysis_run_ids, &compact_ids([review["analysis_run_id"] | &1]))
    |> Map.update!(:candidate_ids, &compact_ids([review["candidate_id"] | &1]))
    |> Map.update!(:revision_ids, fn ids ->
      compact_ids([
        review["base_revision_id"],
        review["candidate_revision_id"],
        review["packet_source_revision_id"] | ids
      ])
    end)
  end

  defp lineage_kind(row, lineage) do
    cond do
      row["id"] in lineage.analysis_run_ids ->
        "analysis_run"

      is_binary(row["session_id"]) and row["session_id"] in lineage.session_ids ->
        "session"

      is_binary(row["candidate_id"]) and row["candidate_id"] in lineage.candidate_ids ->
        "candidate"

      legacy_revision?(row, lineage) ->
        "legacy_revision"

      true ->
        "unbound"
    end
  end

  defp legacy_revision?(row, lineage) do
    is_nil(row["session_id"]) and is_nil(row["candidate_id"]) and
      row["revision_id"] in lineage.revision_ids
  end

  defp compact_ids(values) do
    values
    |> List.flatten()
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp selected_candidate_id(run, progress) do
    run["selected_candidate_id"] ||
      progress
      |> Map.get("steps", [])
      |> List.wrap()
      |> Enum.reverse()
      |> Enum.find_value(fn step -> get_in(step, ["result", "candidate_id"]) end)
  end

  defp query_rows(repo, statement, params) do
    case SQL.query(repo, statement, params, log: false) do
      {:ok, result} -> rows(result)
      {:error, _} -> []
    end
  end

  defp rows(%{columns: columns, rows: rows}) do
    Enum.map(rows, fn values ->
      columns
      |> Enum.zip(values)
      |> Map.new(fn {column, value} -> {column, decode(column, value)} end)
    end)
  end

  defp decode(column, <<_::binary-size(16)>> = value) when column in @uuid_text_columns do
    case Ecto.UUID.load(value) do
      {:ok, uuid} -> uuid
      _ -> value
    end
  end

  defp decode(_column, value), do: value
end
