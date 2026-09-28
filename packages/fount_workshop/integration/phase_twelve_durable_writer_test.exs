Code.require_file("../support/scripted_completion.ex", __DIR__)

defmodule FountWorkshop.PhaseTwelveDurableWriterTest do
  use ExUnit.Case, async: false
  alias Fount.{ID, Persistence, Repo, Screenplay}
  alias FountWorkshop.{Acceptance, Candidate, Discovery, Session, Store}
  alias FountWorkshop.TestSupport.ScriptedCompletion

  setup_all do
    start_supervised!({Repo, url: System.fetch_env!("FOUNT_DATABASE_URL"), pool_size: 2})
    :ok
  end

  test "saved brief reaches execution; writer edit acceptance is durable, stale-safe and idempotent" do
    base = Screenplay.new()
    key = "phase12-#{ID.v4()}"
    assert {:ok, _} = Persistence.create(Repo, key, base)
    services = %{store: Store.new(Repo)}

    request = %{
      "version" => 1,
      "workflow" => "develop",
      "mode" => "draft",
      "base_revision_id" => base.revision.id,
      "instruction" => "Begin at the pool.",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "options" => %{
        "placement" => %{"kind" => "start"},
        "protected_strengths" => ["wet paper map"]
      }
    }

    assert {:ok, opened} = Session.open(base, request, services)

    assert {:ok, _} =
             Discovery.update_brief(
               opened["id"],
               %{"desired_experience" => "Uneasy recognition"},
               services
             )

    parent = self()

    strategy = %{
      "id" => "pool",
      "title" => "At the gate",
      "premise_of_change" => "They pause",
      "dramatic_mechanism" => "The map divides them",
      "entry_state" => "Estranged",
      "exit_state" => "Still estranged",
      "beats" => [],
      "preserves" => ["wet paper map"],
      "changes" => [],
      "inventions" => [],
      "consequences" => [],
      "evidence_ids" => [],
      "open_questions" => []
    }

    {:ok, script} =
      Agent.start_link(fn ->
        [
          fn prompt ->
            send(parent, {:prompt, inspect(prompt)})
            %{"strategies" => [strategy]}
          end
        ]
      end)

    on_exit(fn -> if Process.alive?(script), do: Agent.stop(script) end)
    inference = Inference.Client.new!(adapter: ScriptedCompletion, adapter_opts: [script: script])

    assert {:ok, _} =
             Session.resume(opened["id"], Map.put(services, :inference, inference),
               strategy_ids: []
             )

    assert_receive {:prompt, prompt}
    assert prompt =~ "Uneasy recognition"
    assert {:ok, before_edit} = Session.resume_view(opened["id"], services)
    assert before_edit["request"]["mode"] == "draft"
    assert get_in(before_edit, ["request", "options", "intended_effect"]) == nil

    insert = %{
      "kind" => "insert_scene",
      "value" => %{
        "after_scene_id" => nil,
        "scene" => %{
          "local_id" => "new:pool",
          "heading" => "EXT. CLOSED POOL - NIGHT",
          "elements" => [
            %{
              "local_id" => "new:map",
              "type" => "action",
              "text" => "They fold a wet paper map.",
              "attrs" => %{}
            }
          ]
        }
      }
    }

    assert {:ok, first} = Candidate.manual(opened["id"], [insert], services, actor: "writer")

    sibling_insert =
      put_in(insert, ["value", "scene", "elements", Access.at(0), "text"], "They hide the map.")

    assert {:ok, sibling} =
             Candidate.manual(opened["id"], [sibling_insert], services, actor: "writer")

    action = Enum.find(first["screenplay"].ir.elements, &(&1.type == :action))

    edit = %{
      "kind" => "replace_text",
      "target" => %{"kind" => "element", "id" => action.id},
      "value" => "They fold the wet map; neither lets go."
    }

    assert {:ok, edited} = Candidate.edit(first["id"], [edit], services, actor: "writer")

    assert {:ok, accepted} =
             Acceptance.accept(edited["id"], base.revision.id, review(edited), services)

    assert {:ok, _} = Discovery.record_acceptance(opened["id"], edited["id"], services)

    assert {:ok, retried} =
             Acceptance.accept(edited["id"], base.revision.id, review(edited), services)

    assert retried.revision.id == accepted.revision.id

    assert {:error, {:stale_revision, current}} =
             Acceptance.accept(sibling["id"], base.revision.id, review(sibling), services)

    assert current == accepted.revision.id
    assert {:ok, _} = Acceptance.reject(sibling["id"], "writer", services)
    assert {:ok, resumed} = Session.resume_view(opened["id"], services)
    decisions = Map.new(resumed["candidates"], &{&1["id"], &1["decision"]})
    assert decisions[edited["id"]] == "accepted"
    assert decisions[sibling["id"]] == "rejected"
    assert resumed["selected_candidate_id"] == edited["id"]
    assert {:ok, head} = Persistence.load(Repo, key)
    assert head.revision.id == accepted.revision.id
  end

  defp review(candidate),
    do: %{
      "candidate_id" => candidate["id"],
      "content_hash" => candidate["screenplay"].revision.content_hash,
      "actor" => "writer",
      "report_ids" => candidate["provenance"]["report_ids"] || [],
      "overrides" => []
    }
end
