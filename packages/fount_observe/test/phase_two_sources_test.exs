defmodule Fount.Observe.PhaseTwoSourcesTest do
  use ExUnit.Case, async: true
  alias Fount.Observe.Cache.ETS
  alias Fount.Observe.{OutputContract, Projection, Question, Recording, Request, Sandbox}
  alias Fount.Writing.CanonicalJSON

  defp model do
    Fount.parse!(
      "INT. ROOM - DAY\n\nMara hides a key. [[The killer is Dan.]]\n\nMARA\nNothing here.\n"
    )
    |> Fount.Screenplay.from_document()
  end

  test "public scene request keeps private notes and source IDs out of model input" do
    m = model()
    {:ok, points} = Projection.points(m, hd(m.ir.scenes).id)
    {:ok, request} = Projection.request(m, "scene", List.last(points), "page_reader")
    bytes = Request.semantic_input(request)
    assert bytes =~ "hides a key"
    refute bytes =~ "killer"
    refute bytes =~ m.revision.id
    refute bytes =~ m.id
    assert request.evidence != []
    assert Enum.all?(request.evidence, &(&1.revision_id == m.revision.id))
    assert [_ | _] = Request.dependencies(request)
  end

  test "human and deterministic records do not fabricate probabilities" do
    {:ok, request} = Request.new(model(), "scene", %{"passage" => "Mara hides a key."})
    contract = OutputContract.literal("project.scene_judgment", %{"type" => "string"})

    for origin <- ["human", "deterministic"] do
      assert {:ok, observation} =
               Recording.record(request, "unclear",
                 contract: contract,
                 origin: origin,
                 producer: "reviewer-or-rule",
                 kind: "scene.intent"
               )

      assert observation.result.distribution == nil
      assert observation.result.value == "unclear"
      assert observation.provenance["origin"] == origin
      assert observation.target == request.target
    end

    assert {:error, _} =
             Recording.record(request, %{"unexpected" => 1},
               contract: contract,
               origin: "human",
               producer: "reviewer",
               kind: "scene.intent"
             )
  end

  test "imported measurements are input-bound and reject stale contract digests" do
    {:ok, request} = Request.new(model(), "scene", %{"passage" => "Mara hides a key."})
    contract = OutputContract.literal("project.scene_judgment", %{"type" => "string"})

    {:ok, original} =
      Recording.record(request, "ambiguous",
        contract: contract,
        origin: "human",
        producer: "reviewer",
        kind: "scene.intent"
      )

    payload = Recording.export(original)
    assert {:ok, imported} = Recording.import_record(request, payload, contract: contract)
    assert imported.result.value == "ambiguous"
    assert imported.provenance["origin"] == "imported"
    refute imported.id == original.id

    assert {:error, %{class: :stale_contract}} =
             Recording.import_record(
               request,
               put_in(payload, ["output_contract", "sha256"], String.duplicate("0", 64)),
               contract: contract
             )

    assert {:error, _} =
             Recording.import_record(%{request | input: %{"passage" => "Dan leaves."}}, payload,
               contract: contract
             )
  end

  test "data-only sandbox fixture files bind questions and semantic input" do
    {:ok, request} = Request.new(model(), "scene", %{"passage" => "Mara hides a key."})
    questions = [q: Question.noul("Is the action visible?")]
    {:ok, fixture} = Sandbox.fixture(request, questions, %{"q" => 0.8})
    packet = %{"id" => "scene-visibility", "fixtures" => [fixture]}

    path =
      Path.join(System.tmp_dir!(), "fount-sandbox-#{System.unique_integer([:positive])}.json")

    File.write!(path, Jason.encode!(packet))
    on_exit(fn -> File.rm(path) end)
    assert {:ok, provider} = Sandbox.load(path)
    {:ok, batch} = Fount.Observe.evaluate(provider, [request], questions)
    assert batch.status == :complete

    {:ok, missing} =
      Fount.Observe.evaluate(
        provider,
        [%{request | input: %{"passage" => "Different"}}],
        questions
      )

    assert hd(missing.entries).error.class == :provider_unconfigured

    stale =
      put_in(fixture, ["output_contracts", Access.at(0), "sha256"], String.duplicate("0", 64))

    File.write!(path, Jason.encode!(%{packet | "fixtures" => [stale]}))
    assert {:ok, stale_provider} = Sandbox.load(path)
    {:ok, stale_batch} = Fount.Observe.evaluate(stale_provider, [request], questions)
    assert hd(stale_batch.entries).error.class == :stale_contract
    File.write!(path, Jason.encode!(%{packet | "fixtures" => [fixture, fixture]}))
    assert {:error, _} = Sandbox.load(path)
    File.write!(path, Jason.encode!(Map.put(packet, "module", "System")))
    assert {:error, _} = Sandbox.load(path)
    assert {:error, _} = Sandbox.load(path, max_bytes: 2)
    assert is_binary(CanonicalJSON.hash(fixture))
  end

  test "record imports cannot relabel an identical input under a different projection" do
    {:ok, request} = Request.new(model(), "scene", %{"passage" => "Mara waits."})
    contract = OutputContract.literal("project.note", %{"type" => "string"})

    {:ok, observation} =
      Recording.record(request, "unclear",
        contract: contract,
        kind: "scene.intent",
        origin: "human",
        producer: "reader"
      )

    assert {:error, _} =
             Recording.import_record(
               %{request | projection_id: "page_reader"},
               Recording.export(observation),
               contract: contract
             )
  end

  test "cache reuse rebinds every exact excerpt and dependency to the current screenplay" do
    first = model()
    second = model()

    {:ok, a_point} =
      Projection.resolve_point(first, %{"kind" => "scene", "id" => hd(first.ir.scenes).id})

    {:ok, b_point} =
      Projection.resolve_point(second, %{"kind" => "scene", "id" => hd(second.ir.scenes).id})

    {:ok, a} = Projection.request(first, "scene", a_point, "page_reader")
    {:ok, b} = Projection.request(second, "scene", b_point, "page_reader")
    {:ok, cache} = ETS.start_link(max_entries: 10)
    on_exit(fn -> if Process.alive?(cache), do: GenServer.stop(cache) end)
    provider = Sandbox.new!(%{"scene" => %{"q" => 0.7}})
    opts = [cache: {ETS, cache}, privacy_namespace: "same-project"]
    {:ok, old} = Fount.Observe.evaluate(provider, [a], [q: Question.noul("Visible?")], opts)
    {:ok, current} = Fount.Observe.evaluate(provider, [b], [q: Question.noul("Visible?")], opts)
    assert current.cache_hits == 1
    before = hd(hd(old.entries).observations)
    after_revision = hd(hd(current.entries).observations)
    assert before.result.id == after_revision.result.id
    assert after_revision.evidence == b.evidence
    assert after_revision.dependencies == Request.dependencies(b)
    assert Enum.all?(after_revision.evidence, &(&1.revision_id == second.revision.id))
    refute before.id == after_revision.id
  end

  test "request provenance must be a map and malformed evidence never reaches materialization" do
    m = model()
    assert {:error, _} = Request.new(m, "scene", %{}, provenance: "not a map")
    {:ok, request} = Request.new(m, "scene", %{})
    assert {:error, _} = Request.validate_envelope(%{request | provenance: []})

    assert {:error, _} =
             Request.validate_envelope(%{request | target: %{request.target | kind: "invented"}})
  end

  test "the packaged semantic fixture is executable through the normal acquisition path" do
    path = Application.app_dir(:fount_observe, "priv/fixtures/scene_visibility.json")
    assert {:ok, provider} = Sandbox.load(path)
    {:ok, request} = Request.new(model(), "any-source-id", %{"text" => "Mara pockets a key."})

    assert {:ok, batch} =
             Fount.Observe.evaluate(provider, [request],
               visible: Question.noul("Is the action observable?")
             )

    assert batch.status == :complete
    assert hd(hd(batch.entries).observations).result.value["probability"] == 0.9
  end
end
