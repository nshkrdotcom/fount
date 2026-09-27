defmodule Fount.Intelligence.PhaseTenDurableAnalysisIntegrationTest do
  use ExUnit.Case, async: false

  alias Fount.Intelligence.Persistence, as: AnalysisStore
  alias Fount.Observe.{Context, Lens, Question, Request, Sandbox}
  alias Fount.Persistence
  alias Fount.Persistence.Analysis
  alias Fount.{ID, Repo, Screenplay}

  setup_all do
    url = System.fetch_env!("FOUNT_DATABASE_URL")
    start_supervised!({Repo, url: url, pool_size: 2})
    :ok
  end

  test "L2 reuse crosses revisions only for identical semantic input and rematerializes current provenance" do
    {root, changed, target_id} = persisted_two_revision_screenplay()
    namespace = "phase10:" <> ID.v4()
    store = AnalysisStore.new(Repo, privacy_namespace: namespace)
    questions = [q: Question.noul("Is Mara still waiting?")]
    lens = context_lens(questions)
    provider = Sandbox.new!(%{"stable" => %{"q" => 0.81}})

    {:ok, first_run} = AnalysisStore.begin(store, root, "scene_doctor")
    first_request = request(root, target_id, "stable", "conceal")

    assert {:ok, first} =
             Fount.Observe.evaluate(
               provider,
               [first_request],
               questions,
               AnalysisStore.measurement_options(first_run, lens: lens)
             )

    assert first.cache_hits == 0
    assert :ok = AnalysisStore.record_batch(first_run, root, first)

    {:ok, second_run} = AnalysisStore.begin(store, changed, "scene_doctor")
    second_request = request(changed, target_id, "stable", "conceal")

    assert {:ok, reused} =
             Fount.Observe.evaluate(
               provider,
               [second_request],
               questions,
               AnalysisStore.measurement_options(second_run, lens: lens)
             )

    assert reused.cache_hits == 1
    assert :ok = AnalysisStore.record_batch(second_run, changed, reused)

    first_observation = hd(hd(first.entries).observations)
    current_observation = hd(hd(reused.entries).observations)
    assert first_observation.result.id == current_observation.result.id
    refute first_observation.id == current_observation.id
    assert current_observation.target.revision_id == changed.revision.id
    assert Enum.all?(current_observation.evidence, &(&1.revision_id == changed.revision.id))

    assert {:ok, second_audit} = Analysis.audit_bundle(Repo, second_run.id)
    assert hd(second_audit["observations"])["revision_id"] == changed.revision.id
    refute inspect(second_audit["observations"]) =~ root.revision.id

    changed_context = request(changed, target_id, "stable", "confess")
    {:ok, context_run} = AnalysisStore.begin(store, changed, "scene_doctor")

    assert {:ok, context_miss} =
             Fount.Observe.evaluate(
               provider,
               [changed_context],
               questions,
               AnalysisStore.measurement_options(context_run, lens: lens)
             )

    assert context_miss.cache_hits == 0

    other_store = AnalysisStore.new(Repo, privacy_namespace: namespace <> ":other")
    {:ok, isolated_run} = AnalysisStore.begin(other_store, changed, "scene_doctor")

    assert {:ok, namespace_miss} =
             Fount.Observe.evaluate(
               provider,
               [second_request],
               questions,
               AnalysisStore.measurement_options(isolated_run, lens: lens)
             )

    assert namespace_miss.cache_hits == 0
  end

  test "audit history survives explicit cache eviction and stores output-contract/resource identity" do
    {root, _changed, _target_id} = persisted_two_revision_screenplay()
    namespace = "phase10-history:" <> ID.v4()
    store = AnalysisStore.new(Repo, privacy_namespace: namespace)

    {:ok, run} =
      AnalysisStore.begin(store, root, "scene_doctor", %{
        "playbook_sha256" => String.duplicate("a", 64),
        "concern" => %{"text" => "Does the scene still turn?"}
      })

    digest = String.duplicate("b", 64)

    assert {:ok, finished} =
             Analysis.finish_run(Repo, run.id, %{
               status: "complete",
               output_contract_id: "intelligence.writer_result_packet",
               output_contract_sha256: digest,
               resource_usage: %{"provider_requests" => 1},
               summary: %{"finding" => "fixture"},
               result: %{"packet" => "retained"},
               metadata: %{"changes_canon" => false}
             })

    assert finished["output_contract_sha256"] == digest
    assert finished["result"] == %{"packet" => "retained"}
    assert {:ok, 0} = AnalysisStore.evict_cache(store, 0)

    assert {:ok, exported} = AnalysisStore.export_run(store, run.id)
    assert {:ok, decoded} = Jason.decode(exported)
    assert decoded["run"]["id"] == run.id
    assert decoded["run"]["result"] == %{"packet" => "retained"}

    assert [usage | _] = AnalysisStore.usage_history(store, root.id, "scene_doctor")
    assert usage["resource_usage"] == %{"provider_requests" => 1}
  end

  test "project assets are host-gated, content-addressed, and cannot name executable hooks" do
    store = AnalysisStore.new(Repo, privacy_namespace: "phase10-assets:" <> ID.v4())
    screenplay = Screenplay.new()
    assert {:ok, _} = Persistence.create(Repo, "phase10-assets-#{ID.v4()}", screenplay)

    content = %{"method" => "identity", "notes" => "project calibration"}

    assert {:error, :project_assets_disabled} =
             AnalysisStore.save_data_asset(
               store,
               screenplay.id,
               "calibration",
               "project.identity",
               content,
               source: %{"label" => "writer room"}
             )

    assert {:error, :executable_analysis_asset_forbidden} =
             AnalysisStore.save_data_asset(
               store,
               screenplay.id,
               "playbook",
               "project.bad",
               %{"module" => "Unsafe.Module"},
               allow_project_assets: true,
               source: %{"label" => "writer room"}
             )

    assert {:ok, stored} =
             AnalysisStore.save_data_asset(
               store,
               screenplay.id,
               "calibration",
               "project.identity",
               content,
               allow_project_assets: true,
               source: %{"label" => "writer room", "owner" => "writer"}
             )

    assert stored["sha256"] == Fount.Writing.CanonicalJSON.hash(content)
    assert stored["enabled"] == false
    assert {:ok, true} = AnalysisStore.set_asset_enabled(store, stored["id"], true)
  end

  defp persisted_two_revision_screenplay do
    root =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. OFFICE - NIGHT",
            elements: [
              %{type: :action, text: "Mara waits by the service door."},
              %{type: :action, text: "Dan checks the hallway clock."}
            ]
          }
        ]
      )

    key = "phase10-reuse-#{ID.v4()}"
    assert {:ok, _} = Persistence.create(Repo, key, root)
    actions = Enum.filter(root.ir.elements, &(&1.type == :action))
    [target, changed_line] = actions

    assert {:ok, changed, _} =
             Screenplay.apply(root, [
               %{
                 "kind" => "replace_text",
                 "target" => %{"kind" => "element", "id" => changed_line.id},
                 "value" => "Dan checks the locked archive door."
               }
             ])

    assert {:ok, ^changed} =
             Persistence.save_edit(Repo, key, changed, expected_revision: root.revision.id)

    {root, changed, target.id}
  end

  defp request(model, element_id, id, intent) do
    element = Fount.Query.node(model, element_id)

    evidence = %{
      "evidence_id" => "evidence-#{element_id}",
      "screenplay_id" => model.id,
      "revision_id" => model.revision.id,
      "target" => %{"kind" => "element", "id" => element_id},
      "excerpt" => element.text,
      "role" => "input_context"
    }

    {:ok, request} =
      Request.new(model, id, %{"passage" => element.text},
        target: %{"kind" => "element", "id" => element_id},
        evidence: [evidence],
        context: %Context{slots: %{"intent" => intent}}
      )

    request
  end

  defp context_lens(questions) do
    {:ok, _compiled, asset} = Lens.compile(questions)

    asset
    |> Map.delete("sha256")
    |> put_in(["context_contract", "optional"], %{"intent" => %{"type" => "literal"}})
  end
end
