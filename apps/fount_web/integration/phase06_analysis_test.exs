defmodule FountWeb.Phase06AnalysisIntegrationTest do
  use FountWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  import FountWeb.AnalysisFixtures
  alias FountWeb.AnalysisDashboard

  test "A01 owner sees complete, partial, failed, not-run and stale evidence states", %{
    conn: conn
  } do
    {:ok, %{run: run, access: access}} = launch("status-matrix")
    {:ok, base} = Fount.Persistence.load(Fount.Repo, access["key"])
    conn = FountWeb.ConnCase.login(conn)
    assert {:ok, _view, empty_html} = live(conn, analysis_path(run, ""))
    assert empty_html =~ "not_run"
    assert empty_html =~ "No saved story connections"
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
      assert {:ok, _view, html} = live(conn, analysis_path(run, "?packet=#{saved.id}"))
      assert html =~ "data-comparison-state"
      assert html =~ state
      assert html =~ saved.id
    end

    {:ok, %{run: stale_run, access: stale_access}} = launch("status-stale")
    {:ok, stale_base} = Fount.Persistence.load(Fount.Repo, stale_access["key"])
    stale = persist_packet(stale_base, "complete", "stale")
    [action | _] = Fount.Query.elements(stale_base, :action)

    {:ok, changed} =
      Fount.Screenplay.apply(
        stale_base,
        Fount.Edit.replace_text(action.id, "A changed candidate revision.")
      )

    {:ok, candidate} =
      Fount.Persistence.save_edit_candidate(Fount.Repo, stale_access["key"], changed)

    SQL.query!(
      Fount.Repo,
      "UPDATE fount_runs SET selected_candidate_id=$2::text::uuid WHERE id=$1::text::uuid",
      [stale_run["id"], candidate.id]
    )

    assert {:ok, _view, stale_html} =
             live(conn, analysis_path(stale_run, "?packet=#{stale.id}"))

    assert {:ok, stale_dashboard} =
             AnalysisDashboard.load(Fount.Repo, "test-owner", stale_run["id"], %{
               "packet" => stale.id
             })

    assert stale_dashboard.selected.state == "stale"
    assert stale_dashboard.review["candidate_id"] == candidate.id
    assert stale_html =~ "stale"
    assert stale_html =~ stale.id
  end

  test "A02 persisted packet inspection is owner scoped, legacy explicit and read-only", %{
    conn: conn
  } do
    {:ok, %{run: run, access: access}} = launch("saved-inspection")
    {:ok, base} = Fount.Persistence.load(Fount.Repo, access["key"])
    saved = persist_packet(base, "complete", "stored")
    legacy = persist_packet(base, "complete", "legacy", legacy: true, observation: false)
    [action | _] = Fount.Query.elements(base, :action)

    {:ok, unrelated_revision} =
      Fount.Screenplay.apply(
        base,
        Fount.Edit.replace_text(action.id, "Not part of this Run lineage.")
      )

    unbound = persist_packet(unrelated_revision, "complete", "unbound")

    before = mutation_counts(run["id"], access["screenplay_id"])

    assert {:ok, dashboard} =
             AnalysisDashboard.load(Fount.Repo, "test-owner", run["id"], %{"packet" => saved.id})

    assert dashboard.selected.packet["finding"] == "Stored finding stored"
    assert dashboard.selected.observations != []
    refute Enum.any?(dashboard.history, &(&1["id"] == unbound.id))

    assert {:error, :not_found} =
             AnalysisDashboard.load(Fount.Repo, "other-owner", run["id"], %{})

    assert before == mutation_counts(run["id"], access["screenplay_id"])

    conn = FountWeb.ConnCase.login(conn)
    assert {:ok, _view, html} = live(conn, analysis_path(run, "?packet=#{legacy.id}"))

    assert {:ok, legacy_dashboard} =
             AnalysisDashboard.load(Fount.Repo, "test-owner", run["id"], %{"packet" => legacy.id})

    assert legacy_dashboard.selected.state == "not_run"
    assert html =~ "legacy / unavailable"
    assert html =~ "This page shows saved analysis"

    assert {:ok, _reconnected, reloaded} =
             live(conn, analysis_path(run, "?packet=#{saved.id}&target=evidence-stored"))

    assert reloaded =~ "Stored finding stored"
    assert reloaded =~ "Stored uncertainty"
    assert before == mutation_counts(run["id"], access["screenplay_id"])
    {:ok, unchanged} = Fount.Persistence.load(Fount.Repo, access["key"])
    assert unchanged.revision.id == base.revision.id
    {:ok, other} = launch("other-packet")
    {:ok, other_base} = Fount.Persistence.load(Fount.Repo, other.access["key"])
    foreign = persist_packet(other_base, "complete", "foreign")

    assert {:ok, scoped} =
             AnalysisDashboard.load(Fount.Repo, "test-owner", run["id"], %{"packet" => foreign.id})

    refute Enum.any?(scoped.history, &(&1["id"] == foreign.id))
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

    assert {:ok, dashboard} =
             AnalysisDashboard.load(Fount.Repo, "test-owner", run["id"], %{"packet" => saved.id})

    assert dashboard.review["base_revision_id"] == original_head
    [action | _] = Fount.Query.elements(base, :action)

    {:ok, changed} =
      Fount.Screenplay.apply(base, Fount.Edit.replace_text(action.id, "Review candidate."))

    {:ok, candidate} = Fount.Persistence.save_edit_candidate(Fount.Repo, access["key"], changed)

    SQL.query!(
      Fount.Repo,
      "UPDATE fount_runs SET selected_candidate_id=$2::text::uuid WHERE id=$1::text::uuid",
      [run["id"], candidate.id]
    )

    {:ok, stored} = Fount.Persistence.candidate(Fount.Repo, candidate.id)

    {:ok, bound} =
      AnalysisDashboard.load(Fount.Repo, "test-owner", run["id"], %{"packet" => saved.id})

    assert bound.review["candidate_id"] == candidate.id
    assert bound.review["candidate_revision_id"] == changed.revision.id
    assert bound.review["check_set_fingerprint"] == stored["check_set_fingerprint"]
    assert is_binary(bound.review["check_set_fingerprint"])
    assert bound.review["packet_id"] == nil
    assert bound.review["freshness"] == "missing"
    assert bound.selected.state == "stale"
    {:ok, still_stored} = Fount.Persistence.candidate(Fount.Repo, candidate.id)
    assert still_stored["required_checks"] == stored["required_checks"]
    assert still_stored["check_set_fingerprint"] == stored["check_set_fingerprint"]
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

    assert {:ok, dashboard} =
             AnalysisDashboard.load(Fount.Repo, "test-owner", run["id"], %{"packet" => saved.id})

    assert dashboard.graph.truncated
    assert dashboard.graph.total_nodes > dashboard.constraints.graph_node_limit
    assert length(dashboard.graph.nodes) == dashboard.constraints.graph_node_limit
    assert hd(dashboard.graph.events).label == "Recorded event 1"
    assert hd(dashboard.graph.events).revision_id == base.revision.id
    assert hd(dashboard.graph.events).evidence_ids == ["evidence-graph"]
    assert Enum.all?(dashboard.graph.nodes, &is_binary(&1.observation_id))
    assert dashboard.graph.explanation =~ "does not establish cause and effect"

    empty = AnalysisDashboard.graph_from_observations([])
    assert empty.nodes == []
    assert empty.events == []
  end

  test "A05 usage distinguishes consumed, open reservations and unknown rows without inspection mutation" do
    {:ok, %{run: run, access: access}} = launch("usage-ledger")
    insert_usage(run, "tokens-reserved", "tokens", 120, nil, "unknown", "reserved")
    insert_usage(run, "tokens-settled", "tokens", 80, 60, "known", "settled")
    insert_usage(run, "tokens-unknown", "tokens", 30, 0, "unknown", "unknown")

    before = mutation_counts(run["id"], access["screenplay_id"])
    assert {:ok, dashboard} = AnalysisDashboard.load(Fount.Repo, "test-owner", run["id"], %{})
    tokens = Enum.find(dashboard.usage.totals, &(&1.resource == "tokens"))
    assert tokens.reserved == 230
    assert tokens.consumed == 60
    assert tokens.outstanding_reserved == 120
    assert tokens.unknown_rows == 2
    assert tokens.unknown_cost_rows == 3
    assert tokens.currencies == ["USD"]
    assert Map.has_key?(dashboard.usage.authoritative_resources, "inference")
    assert Map.has_key?(dashboard.usage.authoritative_resources, "measurement_states")
    assert dashboard.usage.note =~ "not HTTP request counts"
    assert before == mutation_counts(run["id"], access["screenplay_id"])
  end

  test "A06 compatible saved evidence gives factual numeric deltas and incompatible evidence is explicit" do
    {:ok, %{run: run, access: access}} = launch("comparison")
    {:ok, base} = Fount.Persistence.load(Fount.Repo, access["key"])

    left =
      persist_packet(base, "complete", "compare-a", observed: 2, evidence_id: "compare-shared")

    right =
      persist_packet(base, "complete", "compare-b", observed: 5, evidence_id: "compare-shared")

    other =
      persist_packet(base, "complete", "compare-other",
        observed: 8,
        evidence_id: "compare-shared",
        provider: %{"provider" => "different", "model" => "fixture"}
      )

    assert {:ok, comparable} =
             AnalysisDashboard.load(Fount.Repo, "test-owner", run["id"], %{
               "left" => left.id,
               "right" => right.id
             })

    assert comparable.comparison.state == :comparable
    assert comparable.comparison.uncertainty.left == ["Stored uncertainty"]
    assert comparable.comparison.uncertainty.right == ["Stored uncertainty"]

    assert Enum.any?(
             comparable.comparison.deltas,
             &(&1.path == "coverage.observed" and &1.delta == 3)
           )

    assert {:ok, incompatible} =
             AnalysisDashboard.load(Fount.Repo, "test-owner", run["id"], %{
               "left" => left.id,
               "right" => other.id
             })

    assert incompatible.comparison.state == :incomparable

    assert Enum.any?(
             incompatible.comparison.reasons,
             &String.contains?(&1, "provider/model fingerprint")
           )
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

    assert {:ok, dashboard} =
             AnalysisDashboard.load(Fount.Repo, "test-owner", run["id"], %{"packet" => saved.id})

    assert dashboard.selected.run["lineage_kind"] == "legacy_revision"

    token = FountWeb.ScreenplayViews.token(evidence)

    assert {:ok, workspace} =
             FountWeb.ScreenplayViews.load(Fount.Repo, access, run, progress, token)

    assert workspace.screenplay.revision.id == base.revision.id

    assert {:error, :stale_or_unbound_revision} =
             FountWeb.ScreenplayViews.load(
               Fount.Repo,
               access,
               run,
               progress,
               "evidence:#{Fount.ID.v4()}:#{base.revision.id}"
             )

    {:ok, unchanged} = Fount.Persistence.load(Fount.Repo, access["key"])
    assert unchanged.revision.id == base.revision.id
  end

  test "authoring exact approval waits for the live connection", %{conn: conn} do
    {:ok, %{run: run, access: access}} = launch("authoring-connection")
    {:ok, workspace} = FountWeb.Authoring.open_workspace("test-owner", access["project_id"])
    raw = String.replace(workspace.draft["raw_source"], "departure board", "blue departure board")

    {:ok, saved, _} =
      FountWeb.Authoring.save_draft(
        "test-owner",
        workspace.draft["id"],
        workspace.draft["version"],
        raw
      )

    {:ok, _bound, _candidate, _} =
      FountWeb.Authoring.save_candidate("test-owner", saved["id"], saved["version"])

    conn = FountWeb.ConnCase.login(conn)
    html = conn |> get(editor_path(run)) |> html_response(200)
    assert html =~ ~r/<button[^>]*id="candidate-accept"[^>]*disabled/
    assert {:ok, view, _html} = live(conn, editor_path(run))
    refute has_element?(view, "#candidate-accept[disabled]")
  end

  defp analysis_path(run, suffix) do
    {:ok, access} = FountWeb.Store.run_access(Fount.Repo, "test-owner", run["id"])
    "/p/#{access["key"]}/analysis/#{access["display_key"]}" <> suffix
  end

  defp editor_path(run) do
    {:ok, access} = FountWeb.Store.run_access(Fount.Repo, "test-owner", run["id"])
    "/p/#{access["key"]}/write"
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

  defp mutation_counts(run_id, screenplay_id) do
    %{rows: [[analysis]]} =
      SQL.query!(
        Fount.Repo,
        "SELECT count(*) FROM analysis_runs WHERE screenplay_id=$1::text::uuid",
        [screenplay_id]
      )

    %{rows: [[usage]]} =
      SQL.query!(Fount.Repo, "SELECT count(*) FROM fount_run_usage WHERE run_id=$1::text::uuid", [
        run_id
      ])

    %{rows: [[requests]]} =
      SQL.query!(
        Fount.Repo,
        "SELECT count(*) FROM fount_run_provider_requests WHERE run_id=$1::text::uuid",
        [run_id]
      )

    %{rows: [[observations]]} =
      SQL.query!(
        Fount.Repo,
        "SELECT count(*) FROM analysis_observations WHERE screenplay_id=$1::text::uuid",
        [screenplay_id]
      )

    %{rows: [[candidates]]} =
      SQL.query!(
        Fount.Repo,
        "SELECT count(*) FROM writing_candidates WHERE screenplay_id=$1::text::uuid",
        [screenplay_id]
      )

    %{rows: [[steps]]} =
      SQL.query!(Fount.Repo, "SELECT count(*) FROM fount_run_steps WHERE run_id=$1::text::uuid", [
        run_id
      ])

    %{
      analysis: analysis,
      observations: observations,
      candidates: candidates,
      steps: steps,
      usage: usage,
      requests: requests
    }
  end
end
