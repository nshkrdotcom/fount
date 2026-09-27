Code.require_file("../support/scripted_completion.ex", __DIR__)

defmodule FountWorkshop.PhaseNineWriterLoopTest do
  use ExUnit.Case, async: false

  alias Fount.{ID, Persistence, Repo, Screenplay}
  alias Fount.Intelligence.Acquisition.CapabilityMeasurements
  alias Fount.Observe.Sandbox
  alias FountWorkshop.{Review, Session, Store}
  alias FountWorkshop.TestSupport.ScriptedCompletion

  setup_all do
    start_supervised!({Repo, url: System.fetch_env!("FOUNT_DATABASE_URL"), pool_size: 2})
    :ok
  end

  test "a measured two-route writer session rejects one branch and accepts the reviewed branch" do
    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. SERVICE OFFICE - NIGHT",
            elements: [%{type: :action, text: "Mara keeps one hand on the sealed ledger."}]
          }
        ]
      )

    key = "phase-nine-writer-#{ID.v4()}"
    assert {:ok, _} = Persistence.create(Repo, key, base)
    [scene] = base.ir.scenes
    action = List.last(base.ir.elements)

    request = %{
      "version" => 1,
      "workflow" => "alternatives",
      "mode" => "revise",
      "base_revision_id" => base.revision.id,
      "instruction" => "Make Mara's choice cost her something visible.",
      "selection" => %{"targets" => [%{"kind" => "scene", "id" => scene.id}]},
      "constraints" => [],
      "alternatives" => 2,
      "options" => %{
        "protected_strengths" => ["Mara's refusal stays quiet."],
        "intended_effect" => "Raise pressure through action."
      }
    }

    scene_spec = CapabilityMeasurements.scene_engine()
    revision_spec = CapabilityMeasurements.revision_intelligence()

    fixtures = %{
      scene.id =>
        Map.new(
          ~w(problem decision plan relationship consequence objective information),
          &{&1, 0.9}
        ),
      "capability:scene_engine:scene:#{scene.id}" => answers(scene_spec["questions"]),
      "capability:revision_intelligence:scene:#{scene.id}" => answers(revision_spec["questions"])
    }

    {:ok, script} =
      Agent.start_link(fn ->
        [
          fn _ -> %{"summary" => "Mara guards the ledger.", "records" => []} end,
          fn _ -> strategies() end,
          fn _ ->
            proposal(
              base,
              action.id,
              "a",
              "Mara tears the ledger seal and loses her hiding place."
            )
          end,
          fn _ ->
            proposal(base, action.id, "b", "Mara hands Dan the ledger and gives up control.")
          end
        ]
      end)

    inference = Inference.Client.new!(adapter: ScriptedCompletion, adapter_opts: [script: script])
    services = %{store: Store.new(Repo), inference: inference, observe: Sandbox.new!(fixtures)}

    assert {:ok, preflight} = Session.preflight(base, request)
    assert preflight["changes_canon"] == false
    assert preflight["analysis"]["playbook"] == "scene_doctor"
    assert Agent.get(script, & &1) |> length() == 4

    assert {:ok, session} = Session.start(base, request, services)
    assert {:ok, loaded} = Session.get(session["id"], services)
    assert loaded["writer_packet"]["status"] in ["complete", "partial"]
    assert length(loaded["candidates"]) == 2
    assert Agent.get(script, & &1) == []

    candidates = Map.new(loaded["candidates"], &{&1["strategy"]["id"], &1})
    rejected = candidates["a"]
    selected = candidates["b"]
    assert {:ok, rejected_packet} = Review.packet(Repo, rejected["id"])
    assert {:ok, packet} = Review.packet(Repo, selected["id"])
    assert packet["original_fountain"] =~ "sealed ledger"
    assert packet["proposed_fountain"] =~ "gives up control"
    assert packet["source_diff"] != []
    assert packet["writer_packet"]["id"] == loaded["writer_packet"]["id"]
    assert packet["revision_packet"]["playbook"] == "revision_regression"
    assert packet["strategy_lineage"]["playbook"] == "scene_doctor"

    assert Enum.all?(
             packet["checks"],
             &(&1["severity"] != "advisory" or &1["kind"] == "revision_intelligence")
           )

    assert {:ok, _} = Review.reject(Repo, rejected["id"], "fixture-writer")
    assert {:ok, head_before} = Persistence.load(Repo, key)
    assert head_before.revision.id == base.revision.id

    assert {:error, _} =
             Review.accept(
               Repo,
               selected["id"],
               base.revision.id,
               review(selected["id"], "wrong-hash", packet)
             )

    assert {:ok, accepted} =
             Review.accept(
               Repo,
               selected["id"],
               base.revision.id,
               review(selected["id"], packet["content_hash"], packet)
             )

    assert {:ok, head} = Persistence.load(Repo, key)
    assert head.revision.id == accepted.revision.id
    assert Screenplay.to_fountain(head) =~ "gives up control"
    history = Persistence.history(Repo, base.id)
    assert length(history) >= 2
    assert rejected_packet["content_hash"] != packet["content_hash"]
  end

  defp strategies do
    %{
      "strategies" => [
        strategy("a", "Break the seal", "Mara destroys the hiding place", "Self-exposure"),
        strategy("b", "Give up control", "Mara entrusts Dan with the ledger", "Transfer of power")
      ]
    }
  end

  defp strategy(id, title, premise, mechanism) do
    %{
      "id" => id,
      "title" => title,
      "premise_of_change" => premise,
      "dramatic_mechanism" => mechanism,
      "entry_state" => "Guarded",
      "exit_state" => "Exposed",
      "beats" => [premise],
      "preserves" => ["Quiet refusal"],
      "changes" => [mechanism],
      "inventions" => [],
      "consequences" => [premise],
      "evidence_ids" => [],
      "open_questions" => []
    }
  end

  defp proposal(base, action_id, id, text) do
    %{
      "version" => 1,
      "base_revision_id" => base.revision.id,
      "strategy_id" => id,
      "summary" => text,
      "inventions" => [],
      "unresolved_questions" => [],
      "groups" => [
        %{
          "id" => "choice",
          "title" => "Visible choice",
          "reason" => "Raise pressure",
          "depends_on" => [],
          "addresses_notes" => [],
          "evidence_ids" => [],
          "origin" => "generated_text",
          "operations" => [
            %{
              "kind" => "replace_text",
              "target" => %{"kind" => "element", "id" => action_id},
              "value" => text
            }
          ]
        }
      ]
    }
  end

  defp review(id, hash, packet),
    do: %{
      "candidate_id" => id,
      "content_hash" => hash,
      "actor" => "fixture-writer",
      "report_ids" => packet["report_ids"],
      "overrides" => []
    }

  defp answers(questions) do
    Map.new(questions, fn {key, question} ->
      value =
        case question.kind do
          :noul ->
            0.9

          :score ->
            0

          :choice ->
            labels = Enum.map(question.criteria, &elem(&1, 0))
            chosen = hd(labels)
            rest = if length(labels) > 1, do: 0.1 / (length(labels) - 1), else: 0.0

            %{
              "probabilities" => Map.new(labels, &{&1, if(&1 == chosen, do: 0.9, else: rest)}),
              "choice" => chosen,
              "confidence" => 0.9
            }
        end

      {to_string(key), value}
    end)
  end
end
