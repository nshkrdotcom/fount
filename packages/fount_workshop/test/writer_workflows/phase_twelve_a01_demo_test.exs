Code.require_file("../../support/continuation_store.ex", __DIR__)
Code.require_file("../../support/scripted_completion.ex", __DIR__)

defmodule FountWorkshop.PhaseTwelveA01DemoTest do
  use ExUnit.Case, async: true

  alias Fount.Screenplay
  alias Fount.Writing.CanonicalJSON
  alias FountWorkshop.{Acceptance, Discovery, Session, Store, Strategy}
  alias FountWorkshop.TestSupport.{ContinuationStore, ScriptedCompletion}

  test "A01 offers three materially different pool openings and resumes accepted plus unchosen routes" do
    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "EXT. CLOSED SWIMMING POOL - NIGHT",
            elements: [
              %{
                type: :action,
                text: "Two estranged siblings fold a wet paper map beside the chained gate."
              }
            ]
          }
        ]
      )

    action = Enum.find(base.ir.elements, &(&1.type == :action))
    {:ok, repo} = ContinuationStore.start_link(base)
    on_exit(fn -> if Process.alive?(repo), do: Agent.stop(repo) end)
    store = %Store{repo: repo, module: ContinuationStore}

    treatments = [
      %{
        "id" => "gate",
        "mechanism_kind" => "action",
        "instruction" => "Begin with a failed physical attempt to enter."
      },
      %{
        "id" => "handoff",
        "mechanism_kind" => "relationship",
        "instruction" => "Begin with one sibling refusing to take the map."
      },
      %{
        "id" => "mark",
        "mechanism_kind" => "revelation",
        "instruction" => "Begin when folding the map exposes one unexplained mark."
      }
    ]

    request = %{
      "version" => 1,
      "workflow" => "alternatives",
      "mode" => "explore",
      "base_revision_id" => base.revision.id,
      "instruction" =>
        "Give me three ways this scene might begin. Do not commit to a global plot.",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "alternatives" => 3,
      "options" => %{
        "treatments" => treatments,
        "allow_brief_departure" => false,
        "protected_strengths" => ["wet paper map"],
        "pending_question" =>
          "Which opening makes their estrangement playable without explaining it?"
      }
    }

    strategies = [
      route("gate", "action", "They test the gate before either will ask the other for help."),
      route("handoff", "relationship", "The map changes hands badly before the first line."),
      route("mark", "revelation", "A mark appears only when the wet map is folded.")
    ]

    {:ok, script} =
      Agent.start_link(fn ->
        [
          fn _ -> %{"strategies" => strategies} end,
          fn _ ->
            proposal(
              base,
              action.id,
              "gate",
              "Evan shoulders the chained gate. Nora keeps folding the wet paper map."
            )
          end,
          fn _ ->
            proposal(
              base,
              action.id,
              "handoff",
              "Nora offers the wet paper map. Evan leaves it hanging between them."
            )
          end,
          fn _ ->
            proposal(
              base,
              action.id,
              "mark",
              "They fold the wet paper map. A red X bleeds through from the other side."
            )
          end
        ]
      end)

    on_exit(fn -> if Process.alive?(script), do: Agent.stop(script) end)
    inference = Inference.Client.new!(adapter: ScriptedCompletion, adapter_opts: [script: script])
    services = %{store: store, inference: inference}

    assert {:ok, session} = Session.open(base, request, %{store: store})

    context = %{
      data: %{
        "selected_pages" => [
          %{"scene_id" => hd(base.ir.scenes).id, "text" => Screenplay.to_fountain(base)}
        ],
        "inspections" => []
      },
      evidence: []
    }

    assert {:ok, generated, [_]} =
             Strategy.generate(nil, session["request"], context, %{inference: inference},
               force_json_text: true
             )

    prepared =
      session
      |> Map.put("strategies", generated)
      |> put_in(["progress", "preparation"], cached_preparation(base, context.data))
      |> Map.put("status", "strategies_ready")

    assert {:ok, _} = Store.call(store, :save_session, [prepared])

    assert {:ok, _} =
             Strategy.materialize(session["id"], Enum.map(generated, & &1["id"]), services)

    assert {:ok, state} = Session.get(session["id"], %{store: store})
    assert length(state["candidates"]) == 3

    pages = Enum.map(state["candidates"], &Screenplay.to_fountain(&1["screenplay"]))
    assert Enum.all?(pages, &String.contains?(&1, "map"))
    assert Enum.any?(pages, &String.contains?(&1, "shoulders the chained gate"))
    assert Enum.any?(pages, &String.contains?(&1, "leaves it hanging between them"))
    assert Enum.any?(pages, &String.contains?(&1, "red X bleeds through"))
    assert ContinuationStore.head(repo).revision.id == base.revision.id

    [chosen, rejected, unchosen] = state["candidates"]

    assert {:ok, accepted} =
             FountWorkshop.TestApproval.accept(%{store: store}, chosen["id"])

    assert {:ok, _} = Discovery.record_acceptance(session["id"], chosen["id"], %{store: store})
    assert {:ok, _} = Acceptance.reject(rejected["id"], "writer", %{store: store})

    assert {:ok, resumed} = Session.resume_view(session["id"], %{store: store})

    assert resumed["pending_question"] ==
             "Which opening makes their estrangement playable without explaining it?"

    assert resumed["selected_candidate_id"] == chosen["id"]
    assert resumed["discovery"]["brief"]["protected_strengths"] == ["wet paper map"]

    decisions = Map.new(resumed["candidates"], &{&1["id"], &1["decision"]})
    assert decisions[chosen["id"]] == "accepted"
    assert decisions[rejected["id"]] == "rejected"
    assert decisions[unchosen["id"]] == "proposed"
    assert ContinuationStore.head(repo).revision.id == accepted.revision.id
  end

  defp route(id, kind, mechanism) do
    %{
      "id" => id,
      "title" => String.capitalize(id),
      "premise_of_change" => mechanism,
      "dramatic_mechanism" => mechanism,
      "entry_state" => "Estranged",
      "exit_state" => "Still unresolved",
      "beats" => [mechanism],
      "preserves" => ["wet paper map"],
      "changes" => [id],
      "inventions" => [],
      "consequences" => ["The opening establishes a different immediate pressure."],
      "evidence_ids" => [],
      "open_questions" => [],
      "treatment_id" => id,
      "mechanism_kind" => kind,
      "tradeoffs" => ["Foregrounding this mechanism delays a different kind of information."],
      "brief_departure" => %{"departed" => false, "reason" => nil}
    }
  end

  defp proposal(base, action_id, strategy_id, text) do
    %{
      "version" => 1,
      "base_revision_id" => base.revision.id,
      "strategy_id" => strategy_id,
      "summary" => text,
      "inventions" => [],
      "unresolved_questions" => [],
      "groups" => [
        %{
          "id" => "opening-#{strategy_id}",
          "title" => "Opening #{strategy_id}",
          "reason" => "Materialize one requested opening mechanism.",
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

  defp cached_preparation(base, data) do
    %{
      "status" => "complete",
      "context_sha256" => CanonicalJSON.hash(data),
      "context" => %{
        "data" => data,
        "evidence" => [],
        "selection" => %{"whole_screenplay" => true},
        "source_revision_ids" => [base.revision.id],
        "historical_revisions" => [],
        "historical" => false,
        "investigation_strategies" => nil
      }
    }
  end
end
