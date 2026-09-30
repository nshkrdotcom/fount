defmodule FountWeb.Phase06AnalysisIntegrationTest do
  use FountWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Fount.Persistence.Analysis
  alias FountWeb.AnalysisDashboard

  test "A01 owner sees complete, partial, failed, not-run and stale evidence states", %{conn: conn} do
    {:ok, %{run: run, access: access}} = launch("status-matrix")
    {:ok, base} = Fount.Persistence.load(Fount.Repo, access["key"])
    complete = persist_packet(base, "complete", "complete")
    partial = persist_packet(base, "partial", "partial")
    failed = persist_packet(base, "failed", "failed")
    running = persist_packet(base, "running", "running")

    conn = FountWeb.ConnCase.login(conn)

    for {saved, state} <- [
          {complete, "complete"},
          {partial, "partial"},
          {failed, "failed"},
          {running, "not_run"}
        ] do
      assert {:ok, _view, html} = live(conn, "/runs/#{run["id"]}/analysis?packet=#{saved.id}")
      assert html =~ "data-comparison-state"
      assert html =~ state
      assert html =~ saved.id
    end

    {:ok, %{run: stale_run, access: stale_access}} = launch("status-stale")
    {:ok, stale_base} = Fount.Persistence.load(Fount.Repo, stale_access["key"])
    stale = persist_packet(stale_base, "complete", "stale")
    [action | _] = Fount.Query.elements(stale_base, :action)
    {:ok, changed} = Fount.Screenplay.apply(stale_base, Fount.Edit.replace_text(action.id, "A changed candidate revision."))
    {:ok, candidate} = Fount.Persistence.save_edit_candidate(Fount.Repo, stale_access["key"], changed)

    SQL.query!(
      Fount.Repo,
      "UPDATE fount_runs SET selected_candidate_id=$2::text::uuid WHERE id=$1::text::uuid",
      [stale_run["id"], candidate["id"]]
    )

    assert {:ok, _view, stale_html} =
             live(conn, "/runs/#{stale_run["id"]}/analysis?packet=#{stale.id}")

    assert stale_html =~ "stale"
    assert stale_html =~ stale.id
  end

  test "A02 persisted packet inspection is owner scoped, legacy explicit and read-only", %{conn: conn} do
    {:ok, %{run: run, access: access}} = launch("saved-inspection")
    {:ok, base} = Fount.Persistence.load(Fount.Repo, access["key"])
    saved = persist_packet(base, "complete", "stored")
    legacy = persist_packet(base, "complete", "legacy", legacy: true, observation: false)
    [action | _] = Fount.Query.elements(base, :action)
    {:ok, unrelated_revision} = Fount.Screenplay.apply(base, Fount.Edit.replace_text(action.id, "Not part of this Run lineage."))
    unbound = persist_packet(unrelated_revision, "complete", "unbound")

    before = mutation_counts(run["id"], access["screenplay_id"])
    assert {:ok, dashboard} = AnalysisDashboard.load(Fount.Repo, "test-owner", run["id"], %{"packet" => saved.id})
    assert dashboard.selected.packet["finding"] == "Stored finding stored"
    assert dashboard.selected.observations != []
    refute Enum.any?(dashboard.history, &(&1["id"] == unbound.id))
    assert {:error, :not_found} = AnalysisDashboard.load(Fount.Repo, "other-owner", run["id"], %{})
    assert before == mutation_counts(run["id"], access["screenplay_id"])

    conn = FountWeb.ConnCase.login(conn)
    assert {:ok, _view, html} = live(conn, "/runs/#{run["id"]}/analysis?packet=#{legacy.id}")
    assert html =~ "legacy / unavailable"
    assert html =~ "Inspection reads saved rows only"
    assert before == mutation_counts(run["id"], access["screenplay_id"])
  end

  test "A03 review binding keeps exact candidate/check identities and inspection never changes canon" do
    {:ok, %{run: run, access: access}} = launch("review-binding")
    {:ok, base} = Fount.Persistence.load(Fount.Repo, access["key"])
    original_head = base.revision.id
    saved = persist_packet(base, "complete", "review")
    {:ok, context} = FountWeb.Actors.owner_context("test-owner", run["screenplay_id"])
    {:ok, progress} = FountRun.progress(Fount.Repo, run["id"], context)
    binding = AnalysisDashboard.review_binding(Fount.Repo, run, progress)

    assert binding["base_revision_id"] == original_head
    assert binding["candidate_id"] == nil
    assert binding["check_set_fingerprint"] == nil
    assert {:ok, dashboard} = AnalysisDashboard.load(Fount.Repo, "test-owner", run["id"], %{"packet" => saved.id})
    assert dashboard.review["base_revision_id"] == original_head
    {:ok, unchanged} = Fount.Persistence.load(Fount.Repo, access["key"])
    assert unchanged.revision.id == original_head
  end

  test "A04 nonempty and oversized stored graphs are bounded and preserve ordered events" do
    {:ok, %{run: run, access: access}} = launch("graph")
    {:ok, base} = Fount.Persistence.load(Fount.Repo, access["key"])

    records =
      for index <- 1..70 do
        %{
          "id" => "event-#{index}",
          "record_type" => "event",
          "label" => "Recorded event #{index}",
          "subjects" => ["NORA-#{index}"],
          "evidence_ids" => ["evidence-graph"],
          "uncertainty" => if(rem(index, 2) == 0, do: "low", else: "unknown")
        }
      end

    saved = persist_packet(base, "complete", "graph", story_world_records: records)
    assert {:ok, dashboard} = AnalysisDashboard.load(Fount.Repo, "test-owner", run["id"], %{"packet" => saved.id})
    assert dashboard.graph.truncated
    assert dashboard.graph.total_nodes > dashboard.constraints.graph_node_limit
    assert length(dashboard.graph.nodes) == dashboard.constraints.graph_node_limit
    assert hd(dashboard.graph.events).label == "Recorded event 1"
    assert hd(dashboard.graph.events).revision_id == base.revision.id
    assert hd(dashboard.graph.events).evidence_ids == ["evidence-graph"]
    assert Enum.all?(dashboard.graph.nodes, &is_binary(&1.observation_id))
    assert dashboard.graph.explanation =~ "causality is never inferred"

    empty = AnalysisDashboard.graph_from_observations([])
    assert empty.nodes == []
    assert empty.events == []
  end

  test "A05 usage distinguishes consumed, open reservations and unknown rows without inspection mutation" do
    {:ok, %{run: run, access: access}} = launch("usage-ledger")
    insert_usage(run, "tokens-reserved", "tokens", 120, nil, "unknown", "reserved")
    insert_usage(run, "tokens-settled", "tokens", 80, 60, "known", "settled")

    before = mutation_counts(run["id"], access["screenplay_id"])
    assert {:ok, dashboard} = AnalysisDashboard.load(Fount.Repo, "test-owner", run["id"], %{})
    tokens = Enum.find(dashboard.usage.totals, &(&1.resource == "tokens"))
    assert tokens.reserved == 200
    assert tokens.consumed == 60
    assert tokens.outstanding_reserved == 140
    assert tokens.unknown_rows == 1
    assert Map.has_key?(dashboard.usage.authoritative_resources, "inference")
    assert Map.has_key?(dashboard.usage.authoritative_resources, "measurement_states")
    assert dashboard.usage.note =~ "not HTTP request counts"
    assert before == mutation_counts(run["id"], access["screenplay_id"])
  end

  test "A06 compatible saved evidence gives factual numeric deltas and incompatible evidence is explicit" do
    {:ok, %{run: run, access: access}} = launch("comparison")
    {:ok, base} = Fount.Persistence.load(Fount.Repo, access["key"])
    left = persist_packet(base, "complete", "compare-a", observed: 2, evidence_id: "compare-shared")
    right = persist_packet(base, "complete", "compare-b", observed: 5, evidence_id: "compare-shared")
    other = persist_packet(base, "complete", "compare-other", observed: 8, evidence_id: "compare-shared", provider: %{"provider" => "different", "model" => "fixture"})

    assert {:ok, comparable} =
             AnalysisDashboard.load(Fount.Repo, "test-owner", run["id"], %{"left" => left.id, "right" => right.id})

    assert comparable.comparison.state == :comparable
    assert comparable.comparison.uncertainty.left == ["Stored uncertainty"]
    assert comparable.comparison.uncertainty.right == ["Stored uncertainty"]
    assert Enum.any?(comparable.comparison.deltas, &(&1.path == "coverage.observed" and &1.delta == 3))

    assert {:ok, incompatible} =
             AnalysisDashboard.load(Fount.Repo, "test-owner", run["id"], %{"left" => left.id, "right" => other.id})

    assert incompatible.comparison.state == :incomparable
    assert Enum.any?(incompatible.comparison.reasons, &String.contains?(&1, "provider/model fingerprint"))
  end

  test "A07 finding navigation is authorized by analysis-run plus revision and does no edit" do
    {:ok, %{run: run, access: access}} = launch("finding-nav")
    {:ok, base} = Fount.Persistence.load(Fount.Repo, access["key"])
    saved = persist_packet(base, "complete", "nav")
    {:ok, context} = FountWeb.Actors.owner_context("test-owner", run["screenplay_id"])
    {:ok, progress} = FountRun.progress(Fount.Repo, run["id"], context)
    {:ok, options} = FountWeb.ScreenplayViews.options(Fount.Repo, access, run, progress)
    evidence = Enum.find(options, &(&1.kind == :evidence and &1.analysis_run_id == saved.id))
    assert evidence.revision_id == base.revision.id
    assert {:ok, dashboard} = AnalysisDashboard.load(Fount.Repo, "test-owner", run["id"], %{"packet" => saved.id})
    assert dashboard.selected.run["lineage_kind"] == "legacy_revision"

    token = FountWeb.ScreenplayViews.token(evidence)
    assert {:ok, workspace} = FountWeb.ScreenplayViews.load(Fount.Repo, access, run, progress, token)
    assert workspace.screenplay.revision.id == base.revision.id
    assert {:error, :stale_or_unbound_revision} =
             FountWeb.ScreenplayViews.load(Fount.Repo, access, run, progress, "evidence:#{Fount.ID.v4()}:#{base.revision.id}")

    {:ok, unchanged} = Fount.Persistence.load(Fount.Repo, access["key"])
    assert unchanged.revision.id == base.revision.id
  end

  defp launch(suffix) do
    FountWeb.Launch.create("test-owner", %{
      "title" => "Phase 06 #{suffix}",
      "key" => "phase06-analysis-#{suffix}-#{System.unique_integer([:positive])}",
      "journey" => "opening",
      "source" => FountWeb.Journeys.fixture_fountain(),
      "filename" => "phase06.fountain"
    })
  end

  defp persist_packet(screenplay, status, suffix, opts \\ []) do
    run_id = Fount.ID.v4()
    spec_sha = String.duplicate("b", 64)
    contract_sha = String.duplicate("c", 64)
    evidence_sha = String.duplicate("d", 64)
    provider = Keyword.get(opts, :provider, %{"provider" => "sandbox", "model" => "fixture"})
    evidence_id = Keyword.get(opts, :evidence_id, "evidence-#{suffix}")
    target = %{
      "kind" => "scene",
      "id" => screenplay.ir.scenes |> hd() |> Map.fetch!(:id),
      "screenplay_id" => screenplay.id,
      "revision_id" => screenplay.revision.id
    }

    {:ok, _} =
      Analysis.start_run(Fount.Repo, %{
        id: run_id,
        screenplay_id: screenplay.id,
        revision_id: screenplay.revision.id,
        revision_content_sha256: screenplay.revision.content_hash,
        playbook: "phase06-fixture",
        playbook_sha256: String.duplicate("a", 64),
        status: "running",
        concern: %{"kind" => "phase06"},
        intent: %{"inspect" => true},
        scope: %{"scene_ids" => [target["id"]]},
        privacy_namespace: "phase06:#{screenplay.id}",
        preflight: %{},
        metadata: %{"fixture" => true}
      })

    if Keyword.get(opts, :observation, true) do
      records =
        Keyword.get(opts, :story_world_records, [
          %{
            "id" => "event-#{suffix}",
            "record_type" => "event",
            "label" => "Stored event #{suffix}",
            "subjects" => ["NORA"],
            "evidence_ids" => [evidence_id]
          }
        ])

      observation = %{
        id: "observation-#{suffix}-#{Fount.ID.v4()}",
        kind: "story_world",
        target: target,
        evidence: [%{"evidence_id" => evidence_id, "screenplay_id" => screenplay.id, "revision_id" => screenplay.revision.id, "target" => target}],
        dependencies: [],
        provenance: %{"request_id" => "request-#{suffix}"},
        result: %{
          "id" => "result-#{suffix}",
          "provider_fingerprint" => provider,
          "measurement_spec_sha256" => spec_sha,
          "value" => %{"story_world_records" => records}
        },
        metadata: %{}
      }

      {:ok, _} = Analysis.save_observations(Fount.Repo, run_id, screenplay.id, screenplay.revision.id, [observation])
    end

    if status != "running" do
      legacy = Keyword.get(opts, :legacy, false)
      packet = %{
        "id" => "packet-#{suffix}",
        "playbook" => "phase06-fixture",
        "source_revision" => screenplay.revision.id,
        "status" => status,
        "finding" => "Stored finding #{suffix}",
        "evidence" => [
          %{
            "evidence_id" => evidence_id,
            "target" => target,
            "revision_id" => screenplay.revision.id,
            "excerpt" => "Persisted evidence excerpt.",
            "excerpt_sha256" => evidence_sha
          }
        ],
        "diagnoses" => [%{"id" => "diagnosis-#{suffix}", "hypothesis" => "Stored hypothesis", "uncertainty" => "bounded"}],
        "uncertainty" => ["Stored uncertainty"],
        "missing_evidence" => [],
        "coverage" => %{"observed" => Keyword.get(opts, :observed, 2), "possible" => 10},
        "provenance" => %{"measurement_spec_sha256" => spec_sha},
        "resource_usage" => %{}
      }

      attrs = %{
        status: status,
        resource_usage: %{},
        summary: %{"finding" => packet["finding"]},
        result: if(legacy, do: %{}, else: packet),
        metadata: %{"fixture" => true}
      }

      attrs =
        if legacy do
          attrs
        else
          Map.merge(attrs, %{output_contract_id: "writer-packet.v1", output_contract_sha256: contract_sha})
        end

      {:ok, _} = Analysis.finish_run(Fount.Repo, run_id, attrs)
    end

    %{id: run_id, revision_id: screenplay.revision.id}
  end

  defp insert_usage(run, operation_id, resource, reserved, settled, knowledge, reconciliation) do
    settled_at = if reconciliation == "reserved", do: nil, else: DateTime.utc_now()

    SQL.query!(
      Fount.Repo,
      "INSERT INTO fount_run_usage(id,operation_id,run_id,screenplay_id,resource,reserved_quantity,settled_quantity,knowledge_state,reconciliation_state,settled_at) VALUES($1::text::uuid,$2,$3::text::uuid,$4::text::uuid,$5,$6,$7,$8,$9,$10)",
      [Fount.ID.v4(), operation_id <> "-" <> run["id"], run["id"], run["screenplay_id"], resource, reserved, settled, knowledge, reconciliation, settled_at]
    )
  end

  defp mutation_counts(run_id, screenplay_id) do
    %{rows: [[analysis]]} = SQL.query!(Fount.Repo, "SELECT count(*) FROM analysis_runs WHERE screenplay_id=$1::text::uuid", [screenplay_id])
    %{rows: [[usage]]} = SQL.query!(Fount.Repo, "SELECT count(*) FROM fount_run_usage WHERE run_id=$1::text::uuid", [run_id])
    %{rows: [[requests]]} = SQL.query!(Fount.Repo, "SELECT count(*) FROM fount_run_provider_requests WHERE run_id=$1::text::uuid", [run_id])
    %{analysis: analysis, usage: usage, requests: requests}
  end
end
