defmodule FountWeb.Phase06IntegrationTest do
  use FountWeb.ConnCase, async: false

  test "new project form mounts with Fountain upload enabled", %{conn: conn} do
    conn = FountWeb.ConnCase.login(conn)
    assert {:ok, _view, html} = live(conn, "/projects/new")
    assert html =~ "Upload Fountain/FDX"
  end

  test "Run launch waits for the live connection instead of losing an early click", %{conn: conn} do
    conn = FountWeb.ConnCase.login(conn)

    {:ok, %{run: run}} =
      FountWeb.Launch.create("test-owner", %{
        "title" => "Connection gate",
        "key" => "connection-gate",
        "journey" => "opening",
        "source" => FountWeb.Journeys.fixture_fountain()
      })

    path = "/runs/#{run["id"]}/setup"
    html = conn |> get(path) |> html_response(200)
    assert html =~ "Connecting live controls"
    assert html =~ ~r/<button[^>]*disabled[^>]*phx-click="launch"/
    assert {:ok, view, _html} = live(conn, path)
    refute has_element?(view, "button[phx-click=launch][disabled]")
  end

  test "native POST creates a Run for the signed owner without LiveView", %{conn: conn} do
    conn = FountWeb.ConnCase.login(conn)

    response =
      post(conn, "/projects", %{
        "project" => %{
          "title" => "Native form",
          "key" => "native-form",
          "journey" => "opening",
          "source" => FountWeb.Journeys.fixture_fountain()
        }
      })

    location = redirected_to(response)
    assert location =~ ~r{^/runs/[0-9a-f-]+/setup$}
    run_id = location |> String.split("/") |> Enum.at(2)
    assert {:ok, access} = FountWeb.Store.run_access(Fount.Repo, "test-owner", run_id)
    assert access["owner_id"] == "test-owner"
  end

  test "native POST accepts an upload and rejects oversized uploads visibly", %{conn: conn} do
    conn = FountWeb.ConnCase.login(conn)
    path = Path.join(System.tmp_dir!(), "fount-native-#{Fount.ID.v4()}.fountain")
    on_exit(fn -> File.rm(path) end)
    File.write!(path, FountWeb.Journeys.fixture_fountain())
    upload = %Plug.Upload{path: path, filename: "story.fountain", content_type: "text/plain"}

    attrs = %{
      "title" => "Native upload",
      "key" => "native-upload",
      "journey" => "opening",
      "source" => ""
    }

    assert post(conn, "/projects", %{"project" => attrs, "screenplay" => upload})
           |> redirected_to() =~ "/setup"

    File.write!(path, :binary.copy("x", 1_048_577))

    response =
      post(conn, "/projects", %{
        "project" => Map.put(attrs, "key", "native-large"),
        "screenplay" => upload
      })

    assert redirected_to(response) == "/projects/new"
    assert Phoenix.Flash.get(response.assigns.flash, :error) =~ "1 MiB"

    assert {:error, :not_found} =
             FountWeb.Store.project_by_key(Fount.Repo, "test-owner", "native-large")
  end

  test "native POST requires authentication and reports validation failure", %{conn: conn} do
    assert redirected_to(post(conn, "/projects", %{"project" => %{}})) == "/login"

    response =
      conn |> FountWeb.ConnCase.login() |> post("/projects", %{"project" => %{"key" => "!"}})

    assert redirected_to(response) == "/projects/new"
    assert Phoenix.Flash.get(response.assigns.flash, :error) != nil
  end

  test "U01 project intake creates candidate-only Run and exact owner mapping", %{conn: conn} do
    conn = FountWeb.ConnCase.login(conn)

    assert {:ok, %{project: project, run: run}} =
             FountWeb.Launch.create("test-owner", %{
               "title" => "Opening",
               "key" => "u01-opening",
               "journey" => "opening",
               "source" => FountWeb.Journeys.fixture_fountain(),
               "filename" => "fixture.fountain"
             })

    assert project["owner_id"] == "test-owner"
    assert project["id"] =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
    assert project["screenplay_id"] == run["screenplay_id"]
    assert get_in(run, ["policy", "policy", "completion"]) == "candidate"
    assert {:ok, _view, html} = live(conn, "/runs/#{run["id"]}/setup")
    assert html =~ "Produce a checked opening candidate without advancing canon"
    assert html =~ "Candidate only"
    assert html =~ "accepted pages can change canon" or html =~ "Accepted pages can change canon"
  end

  test "U04 wrong run id and wrong owner are denied rather than widened", %{conn: conn} do
    conn = FountWeb.ConnCase.login(conn)

    assert {:ok, %{run: run}} =
             FountWeb.Launch.create("test-owner", %{
               "title" => "Owner scoped",
               "key" => "u04-owner-scope",
               "journey" => "opening",
               "source" => FountWeb.Journeys.fixture_fountain(),
               "filename" => "fixture.fountain"
             })

    assert {:error, :not_found} = FountWeb.Store.run_access(Fount.Repo, "other-owner", run["id"])
    assert {:error, {kind, %{to: "/"}}} = live(conn, "/runs/#{Fount.ID.v4()}/timeline")
    assert kind in [:redirect, :live_redirect]
  end

  test "U04 unauthenticated and wrong-owner sessions cannot view any run surface or artifact", %{
    conn: conn
  } do
    assert {:ok, %{project: project, run: run}} =
             FountWeb.Launch.create("test-owner", %{
               "title" => "Private",
               "key" => "u04-private-surfaces",
               "journey" => "opening",
               "source" => FountWeb.Journeys.fixture_fountain(),
               "filename" => "fixture.fountain"
             })

    assert project["screenplay_id"] == run["screenplay_id"]

    for session <- [%{}, %{owner_id: "other-owner"}],
        path <- [
          "/",
          "/projects/new",
          "/runs/#{run["id"]}/setup",
          "/runs/#{run["id"]}/timeline",
          "/runs/#{run["id"]}/decisions",
          "/runs/#{run["id"]}/review",
          "/runs/#{run["id"]}/exports"
        ] do
      private_conn = Phoenix.ConnTest.init_test_session(conn, session)
      assert {:error, {kind, %{to: "/login"}}} = live(private_conn, path)
      assert kind in [:redirect, :live_redirect]
    end

    for session <- [%{}, %{owner_id: "other-owner"}] do
      private_conn = Phoenix.ConnTest.init_test_session(conn, session)
      response = get(private_conn, "/artifacts/#{run["id"]}/#{Fount.ID.v4()}")
      assert redirected_to(response) == "/login"
      refute response.resp_body =~ "departure board"
    end
  end

  test "standard export form submits without optional checkboxes", %{conn: conn} do
    conn = FountWeb.ConnCase.login(conn)

    assert {:ok, %{run: run}} =
             FountWeb.Launch.create("test-owner", %{
               "title" => "Export form",
               "key" => "u01-export-form",
               "journey" => "opening",
               "source" => FountWeb.Journeys.fixture_fountain(),
               "filename" => "fixture.fountain"
             })

    assert {:ok, view, _html} = live(conn, "/runs/#{run["id"]}/exports")
    assert render_submit(element(view, "form[phx-submit=deliver]")) =~ "Export failed"
  end

  test "storage errors are not shown as an empty project or a missing run" do
    assert {:error, :storage_error} =
             FountWeb.Store.project(Fount.Repo, "test-owner", "invalid-uuid")

    assert {:error, :storage_error} =
             FountWeb.Store.run_access(Fount.Repo, "test-owner", "invalid-uuid")
  end

  test "H01-H05 deterministic host journey persists prewrite/revision analysis and keeps candidate noncanonical" do
    assert {:ok, %{project: project, run: run}} =
             FountWeb.Launch.create("test-owner", %{
               "title" => "Integrated analysis",
               "key" => "h03-integrated-analysis",
               "journey" => "analysis",
               "source" => FountWeb.Journeys.fixture_fountain(),
               "filename" => "fixture.fountain"
             })

    {:ok, context} = FountWeb.Actors.owner_context("test-owner", run["screenplay_id"])

    assert {:ok, step_opts} =
             FountWeb.Services.worker_step_opts("test-owner", run["screenplay_id"], run)

    assert Fount.Observe.Provider.sensor_id(Keyword.fetch!(step_opts, :observe)) == "sandbox"
    assert %Inference.Client{} = Keyword.fetch!(step_opts, :inference)

    for expected <- ["intake", "investigate", "plan"] do
      assert {:ok, %{"status" => "succeeded", "stage" => ^expected}} =
               FountRun.step(Fount.Repo, run["id"], context, step_opts)
    end

    assert {:ok, at_strategy} = FountRun.progress(Fount.Repo, run["id"], context)

    strategy =
      Enum.find(
        at_strategy["decisions"],
        &(&1["kind"] == "strategy" and &1["status"] == "pending")
      )

    assert is_map(strategy)

    assert {:ok, _} =
             FountRun.submit_decision(
               Fount.Repo,
               strategy["id"],
               %{
                 "choice" => "route-a",
                 "context_fingerprint" => strategy["context_fingerprint"],
                 "plan_version" => strategy["plan_version"],
                 "policy_version" => strategy["policy_version"]
               },
               context
             )

    assert {:ok, %{"status" => "succeeded", "stage" => "write"}} =
             FountRun.step(Fount.Repo, run["id"], context, step_opts)

    assert {:ok, %{"status" => "succeeded", "stage" => "check"}} =
             FountRun.step(Fount.Repo, run["id"], context, step_opts)

    assert {:ok, progress} = FountRun.progress(Fount.Repo, run["id"], context)
    prewrite = progress["analysis"] |> Enum.find_value(& &1["writer"])
    revision = progress["analysis"] |> Enum.reverse() |> Enum.find_value(& &1["revision"])
    assert prewrite["status"] in ["complete", "partial"]
    assert revision["status"] in ["complete", "partial"]
    assert is_binary(prewrite["analysis_run_id"])
    assert is_binary(revision["analysis_run_id"])

    for analysis_run_id <- [prewrite["analysis_run_id"], revision["analysis_run_id"]] do
      result =
        Ecto.Adapters.SQL.query!(
          Fount.Repo,
          "SELECT count(*) FROM analysis_runs WHERE id=$1::text::uuid",
          [analysis_run_id]
        )

      assert result.rows == [[1]]

      assert [[count]] =
               Ecto.Adapters.SQL.query!(
                 Fount.Repo,
                 "SELECT count(*) FROM analysis_observations o JOIN analysis_measurement_results m ON m.result_id=o.result_id WHERE o.analysis_run_id=$1::text::uuid",
                 [analysis_run_id]
               ).rows

      assert count > 0
    end

    check = progress["steps"] |> Enum.find(&(&1["stage"] == "check"))
    checks = check["result"]["checks"]

    assert Enum.any?(
             checks,
             &(&1["severity"] == "advisory" and &1["kind"] == "revision_intelligence")
           )

    assert Enum.any?(checks, &(&1["severity"] == "required" and &1["source"] == "run"))

    candidate_id = check["result"]["candidate_id"]
    assert {:ok, candidate} = Fount.Persistence.candidate(Fount.Repo, candidate_id)

    assert get_in(candidate, ["provenance", "revision_intelligence", "status"]) in [
             "complete",
             "partial"
           ]

    assert {:ok, canonical} = Fount.Persistence.load(Fount.Repo, project["key"])
    assert canonical.revision.id == run["plan"]["base_revision_id"]

    assert {:ok, reloaded} = FountRun.progress(Fount.Repo, run["id"], context)
    assert reloaded["analysis"] == progress["analysis"]

    original = Application.fetch_env!(:fount_web, :observe)
    on_exit(fn -> Application.put_env(:fount_web, :observe, original) end)
    canary = "phase03-qc-" <> Fount.ID.v4()

    Application.put_env(:fount_web, :observe,
      mode: :system_one,
      provider_opts: [
        endpoint_kind: :endpoint,
        base_url: "http://127.0.0.1:1",
        model: "contract-only",
        api_key: canary
      ]
    )

    output =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, provider} = FountWeb.Services.observe_provider(run["screenplay_id"], run)
        refute inspect(provider) =~ canary

        Application.put_env(:fount_web, :observe,
          mode: :system_one,
          provider_opts: [
            endpoint_kind: :endpoint,
            base_url: "invalid",
            model: "contract-only",
            api_key: canary
          ]
        )

        assert {:error, :observe_provider_invalid} =
                 FountWeb.WorkerSupervisor.start_run(%{
                   "owner_id" => "test-owner",
                   "screenplay_id" => run["screenplay_id"],
                   "run_id" => run["id"]
                 })
      end)

    refute output =~ canary

    tables =
      Ecto.Adapters.SQL.query!(
        Fount.Repo,
        "SELECT tablename FROM pg_tables WHERE schemaname='public'",
        []
      ).rows

    for [table] <- tables do
      assert [[0]] =
               Ecto.Adapters.SQL.query!(
                 Fount.Repo,
                 "SELECT count(*) FROM \"#{table}\" AS t WHERE row_to_json(t)::text LIKE $1",
                 ["%" <> canary <> "%"]
               ).rows
    end
  end

  test "H04 LiveView reload preserves complete partial failed and not-run safe progress", %{
    conn: conn
  } do
    conn = FountWeb.ConnCase.login(conn)
    original = Application.fetch_env!(:fount_web, :observe)
    on_exit(fn -> Application.put_env(:fount_web, :observe, original) end)

    for status <- ["complete", "partial", "failed", "not_run"] do
      assert {:ok, %{run: run}} =
               FountWeb.Launch.create("test-owner", %{
                 "title" => "Progress classes",
                 "key" => "h04-" <> status,
                 "journey" => "analysis",
                 "source" => FountWeb.Journeys.fixture_fountain(),
                 "filename" => "fixture.fountain"
               })

      {:ok, context} = FountWeb.Actors.owner_context("test-owner", run["screenplay_id"])
      {:ok, opts} = FountWeb.Services.worker_step_opts("test-owner", run["screenplay_id"], run)
      assert {:ok, _step} = FountRun.step(Fount.Repo, run["id"], context, opts)
      summary = %{"status" => status, "analysis_run_id" => Fount.ID.v4()}

      analysis =
        if status == "not_run", do: %{}, else: %{"writer" => summary, "revision" => summary}

      update =
        Ecto.Adapters.SQL.query!(
          Fount.Repo,
          "UPDATE fount_run_steps SET result=jsonb_set(COALESCE(result, '{}'::jsonb), '{analysis}', $2::jsonb) WHERE run_id=$1::text::uuid AND stage='intake'",
          [run["id"], analysis]
        )

      assert update.num_rows == 1
      if status == "not_run", do: Application.put_env(:fount_web, :observe, mode: :compatibility)
      assert {:ok, progress} = FountRun.progress(Fount.Repo, run["id"], context)
      if status != "not_run", do: assert(progress["analysis"] != [], inspect(progress["steps"]))
      if status != "not_run", do: assert(hd(progress["analysis"])["writer"] == summary)

      for _reload <- 1..2 do
        assert {:ok, view, html} = live(conn, "/runs/#{run["id"]}/timeline")
        display = if status == "not_run", do: "not-run", else: status
        assert html =~ "Status: <strong>#{display}</strong>"
        if status == "not_run", do: assert(html =~ "Compatibility (analysis not run)")
        if status != "not_run", do: assert(html =~ summary["analysis_run_id"])

        if status in ["partial", "failed", "not_run"],
          do: refute(html =~ "Status: <strong>complete</strong>")

        GenServer.stop(view.pid)
      end
    end
  end
end
