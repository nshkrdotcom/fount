Code.require_file("../../support/continuation_store.ex", __DIR__)

defmodule FountWorkshop.PhaseTwelveDiscoveryTest do
  use ExUnit.Case, async: true

  alias Fount.Screenplay
  alias FountWorkshop.{Acceptance, Candidate, Discovery, Session, Store}
  alias FountWorkshop.TestSupport.ContinuationStore

  test "provider-free discovery keeps canon unchanged until explicit acceptance and resumes state" do
    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "EXT. CLOSED SWIMMING POOL - NIGHT",
            elements: [%{type: :action, text: "The gate is chained."}]
          },
          %{
            heading: "INT. POOL OFFICE - NIGHT",
            elements: [%{type: :action, text: "A dead clock reads 2:13."}]
          }
        ]
      )

    {:ok, repo} = ContinuationStore.start_link(base)
    on_exit(fn -> if Process.alive?(repo), do: Agent.stop(repo) end)
    services = %{store: %Store{repo: repo, module: ContinuationStore}}

    request = %{
      "version" => 1,
      "workflow" => "develop",
      "mode" => "draft",
      "base_revision_id" => base.revision.id,
      "instruction" => "Start only from the supplied image; do not invent a global plot.",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "options" => %{
        "placement" => %{"kind" => "start"},
        "protected_strengths" => ["the wet paper map"],
        "pending_question" => "Do they recognize the handwriting?"
      }
    }

    assert {:ok, session} = Session.open(base, request, services)
    assert session["request"]["mode"] == "draft"
    assert session["request"]["alternatives"] == 1
    assert get_in(session, ["provenance", "phase9_preflight", "analysis", "status"]) == "not_run"

    assert get_in(session, ["provenance", "phase9_preflight", "analysis", "reason"]) ==
             "no_prewrite_playbook_for_workflow"

    assert ContinuationStore.head(repo).revision.id == base.revision.id

    assert {:ok, image} =
             Discovery.add_fragment(
               session["id"],
               %{
                 "kind" => "image",
                 "content" =>
                   "At a closed swimming pool, two estranged siblings fold a wet paper map."
               },
               services
             )

    assert image["status"] == "unattached"
    assert image["classification"] == "wanted"

    assert {:ok, connective} =
             Discovery.add_fragment(
               session["id"],
               %{
                 "kind" => "line",
                 "content" => "You kept the dry half.",
                 "classification" => "wanted"
               },
               services
             )

    first_scene_id = hd(base.ir.scenes).id

    assert {:ok, classified} =
             Discovery.classify_fragment(session["id"], connective["id"], "connective", services)

    assert classified["classification"] == "connective"

    assert {:ok, linked} =
             Discovery.link_fragment(session["id"], connective["id"], first_scene_id, services)

    assert linked["status"] == "linked"
    assert {:ok, retired} = Discovery.retire_fragment(session["id"], connective["id"], services)
    assert retired["status"] == "retired"

    assert Enum.map(retired["history"], & &1["action"]) == [
             "captured",
             "classified",
             "linked",
             "retired"
           ]

    assert {:ok, brief} =
             Discovery.update_brief(
               session["id"],
               %{
                 "desired_experience" => "Uneasy recognition without explanation",
                 "permission_to_depart" => false
               },
               services
             )

    assert brief["desired_experience"] == "Uneasy recognition without explanation"

    assert {:ok, outline} = Discovery.reverse_outline(session["id"], services)
    assert Enum.map(outline["cards"], & &1["scene_id"]) == Enum.map(base.ir.scenes, & &1.id)
    assert Enum.all?(outline["cards"], &(&1["function_status"] == "unknown"))
    refute outline["changes_canon"]

    reversed = base.ir.scenes |> Enum.map(& &1.id) |> Enum.reverse()
    assert {:ok, reorder} = Discovery.propose_reorder(session["id"], reversed, services)
    refute reorder["changes_canon"]
    assert ContinuationStore.head(repo).revision.id == base.revision.id

    assert {:ok, _} = Discovery.switch_mode(session["id"], "inspect", services)
    assert {:ok, resumed} = Session.resume_view(session["id"], services)
    assert resumed["request"]["mode"] == "draft"
    assert resumed["current_mode"] == "inspect"
    assert resumed["pending_question"] == "Do they recognize the handwriting?"
    assert resumed["discovery"]["brief"]["protected_strengths"] == ["the wet paper map"]

    insert = %{
      "kind" => "insert_scene",
      "value" => %{
        "after_scene_id" => nil,
        "scene" => %{
          "local_id" => "new:pool_open",
          "heading" => "EXT. CLOSED SWIMMING POOL - NIGHT",
          "elements" => [
            %{
              "local_id" => "new:map_action",
              "type" => "action",
              "text" => "Two siblings fold a wet paper map against the locked gate.",
              "attrs" => %{}
            }
          ]
        }
      }
    }

    assert {:ok, first} =
             Candidate.manual(session["id"], [insert], services,
               actor: "writer",
               label: "Pool image"
             )

    assert ContinuationStore.head(repo).revision.id == base.revision.id

    # A second branch exists before either branch is accepted, proving manual capture is a real candidate path.
    alternate_insert =
      put_in(
        insert,
        ["value", "scene", "elements"],
        [
          %{
            "local_id" => "new:map_action_alt",
            "type" => "action",
            "text" => "They fold the wet map without looking at each other.",
            "attrs" => %{}
          }
        ]
      )

    assert {:ok, alternate} =
             Candidate.manual(session["id"], [alternate_insert], services,
               actor: "writer",
               label: "Quiet pool image"
             )

    new_action =
      first["screenplay"].ir.elements
      |> Enum.find(
        &(&1.type == :action and is_binary(&1.text) and String.contains?(&1.text, "wet paper map"))
      )

    assert {:ok, edited} =
             Candidate.edit(
               first["id"],
               [
                 %{
                   "kind" => "replace_text",
                   "target" => %{"kind" => "element", "id" => new_action.id},
                   "value" =>
                     "They fold the wet paper map on the concrete. Neither lets go first."
                 }
               ],
               services,
               actor: "writer"
             )

    assert {:ok, adopted} =
             Discovery.adopt_fragment(session["id"], image["id"], edited["id"], services)

    assert adopted["status"] == "adopted"

    assert {:ok, accepted} = FountWorkshop.TestApproval.accept(services, edited["id"])
    assert accepted.revision.id == edited["screenplay"].revision.id
    assert {:ok, _} = Discovery.record_acceptance(session["id"], edited["id"], services)

    # Retrying the same explicit acceptance remains idempotent and creates no second draft.
    assert {:ok, retried} = FountWorkshop.TestApproval.accept(services, edited["id"])
    assert retried.revision.id == accepted.revision.id

    assert {:error, {:stale_revision, current}} =
             FountWorkshop.TestApproval.accept(services, alternate["id"])

    assert current == accepted.revision.id
    assert {:ok, _} = Acceptance.reject(alternate["id"], "writer", services)

    assert {:ok, restored} = Session.resume_view(session["id"], services)
    decisions = Map.new(restored["candidates"], &{&1["id"], &1["decision"]})
    assert decisions[edited["id"]] == "accepted"
    assert decisions[alternate["id"]] == "rejected"
    assert restored["selected_candidate_id"] == edited["id"]
    assert restored["pending_question"] == "Do they recognize the handwriting?"
    assert restored["optional_next_action"] == "answer_pending_question"
    assert ContinuationStore.head(repo).revision.id == accepted.revision.id
  end
end
