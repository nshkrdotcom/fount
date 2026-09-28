Code.require_file("../../support/continuation_store.ex", __DIR__)
Code.require_file("../../support/scripted_completion.ex", __DIR__)

defmodule FountWorkshop.PhaseTwelveSceneExplorationTest do
  use ExUnit.Case, async: true

  alias Fount.Screenplay
  alias Fount.Writing.CanonicalJSON
  alias FountWorkshop.{Discovery, Session, Store, Strategy}
  alias FountWorkshop.TestSupport.{ContinuationStore, ScriptedCompletion}

  test "three treatment routes become actual candidate pages and keep-both/reject-all remain writer decisions" do
    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "EXT. CLOSED SWIMMING POOL - NIGHT",
            elements: [
              %{type: :action, text: "Nora and Evan fold a wet paper map on the concrete."}
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
        "id" => "conceal",
        "mechanism_kind" => "revelation",
        "instruction" =>
          "Keep the secret withheld; the map remains a pressure point rather than a confession."
      },
      %{
        "id" => "volunteer",
        "mechanism_kind" => "relationship",
        "instruction" =>
          "One sibling chooses to offer the secret, changing the relationship by choice."
      },
      %{
        "id" => "accident",
        "mechanism_kind" => "action",
        "instruction" =>
          "A physical mistake with the wet map exposes the secret without a voluntary confession."
      }
    ]

    request = %{
      "version" => 1,
      "workflow" => "alternatives",
      "mode" => "explore",
      "base_revision_id" => base.revision.id,
      "instruction" => "Give me three genuinely different treatments of the same secret.",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "alternatives" => 3,
      "options" => %{
        "treatments" => treatments,
        "allow_brief_departure" => true,
        "protected_strengths" => ["wet paper map"]
      }
    }

    strategies = strategy_response()

    {:ok, script} =
      Agent.start_link(fn ->
        [
          fn _ -> %{"strategies" => strategies} end,
          fn _ ->
            proposal(
              base,
              action.id,
              "conceal",
              "Evan folds the hotel stamp inward before Nora can read it."
            )
          end,
          fn _ ->
            proposal(
              base,
              action.id,
              "volunteer",
              "Nora opens the map to the hotel stamp. She tells Evan where she found it."
            )
          end,
          fn _ ->
            proposal(
              base,
              action.id,
              "accident",
              "The wet map tears. A hotel receipt skitters between them."
            )
          end
        ]
      end)

    on_exit(fn -> if Process.alive?(script), do: Agent.stop(script) end)

    inference = Inference.Client.new!(adapter: ScriptedCompletion, adapter_opts: [script: script])
    services = %{store: store, inference: inference}

    assert {:ok, opened} = Session.open(base, request, %{store: store})

    context = %{
      data: %{
        "selected_pages" => [
          %{"scene_id" => hd(base.ir.scenes).id, "text" => Screenplay.to_fountain(base)}
        ],
        "inspections" => []
      },
      evidence: []
    }

    assert {:ok, generated_strategies, [_]} =
             Strategy.generate(nil, opened["request"], context, %{inference: inference},
               force_json_text: true
             )

    assert Enum.map(generated_strategies, & &1["treatment_id"]) == [
             "conceal",
             "volunteer",
             "accident"
           ]

    assert Enum.map(generated_strategies, & &1["mechanism_kind"]) == [
             "revelation",
             "relationship",
             "action"
           ]

    assert Enum.any?(generated_strategies, &get_in(&1, ["brief_departure", "departed"]))

    prepared =
      opened
      |> Map.put("strategies", generated_strategies)
      |> put_in(["progress", "preparation"], cached_preparation(base, context.data))
      |> Map.put("status", "strategies_ready")

    assert {:ok, _} = Store.call(store, :save_session, [prepared])

    ids = Enum.map(generated_strategies, & &1["id"])
    assert {:ok, materialized} = Strategy.materialize(opened["id"], ids, services)
    assert materialized["status"] == "review_ready"

    assert {:ok, state} = Session.get(opened["id"], %{store: store})
    assert length(state["candidates"]) == 3

    pages = Enum.map(state["candidates"], &Screenplay.to_fountain(&1["screenplay"]))
    assert Enum.any?(pages, &String.contains?(&1, "folds the hotel stamp inward"))
    assert Enum.any?(pages, &String.contains?(&1, "tells Evan where she found it"))
    assert Enum.any?(pages, &String.contains?(&1, "receipt skitters"))

    [first, second | _] = state["candidates"]

    assert {:ok, _} =
             Discovery.keep_both(opened["id"], [first["id"], second["id"]], %{store: store})

    assert ContinuationStore.head(repo).revision.id == base.revision.id

    candidate_ids = Enum.map(state["candidates"], & &1["id"])
    assert {:ok, _} = Discovery.reject_all(opened["id"], candidate_ids, "writer", %{store: store})

    assert {:ok, after_decision} = Session.get(opened["id"], %{store: store})
    assert Enum.all?(after_decision["candidates"], &(&1["decision"] == "rejected"))

    assert Enum.map(after_decision["discovery"]["decisions"], & &1["action"]) |> Enum.take(-2) ==
             ["keep_both", "reject_all"]

    assert ContinuationStore.head(repo).revision.id == base.revision.id
  end

  test "a three-confession paraphrase fixture cannot masquerade as the requested treatment axes" do
    base = Screenplay.new()
    {:ok, repo} = ContinuationStore.start_link(base)
    on_exit(fn -> if Process.alive?(repo), do: Agent.stop(repo) end)

    request = %{
      "version" => 1,
      "workflow" => "alternatives",
      "mode" => "explore",
      "base_revision_id" => base.revision.id,
      "instruction" => "Conceal, volunteer, or accidentally reveal the secret.",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "alternatives" => 3,
      "options" => %{
        "treatments" => [
          %{"id" => "conceal", "mechanism_kind" => "revelation", "instruction" => "withhold"},
          %{
            "id" => "volunteer",
            "mechanism_kind" => "relationship",
            "instruction" => "choose to tell"
          },
          %{"id" => "accident", "mechanism_kind" => "action", "instruction" => "physical mistake"}
        ],
        "allow_brief_departure" => false
      }
    }

    bad =
      Enum.map(~w(conceal volunteer accident), fn id ->
        treatment_strategy(
          id,
          "revelation",
          "They confess the secret in slightly different words.",
          false
        )
      end)

    {:ok, script} =
      Agent.start_link(fn ->
        [fn _ -> %{"strategies" => bad} end, fn _ -> %{"strategies" => bad} end]
      end)

    on_exit(fn -> if Process.alive?(script), do: Agent.stop(script) end)
    client = Inference.Client.new!(adapter: ScriptedCompletion, adapter_opts: [script: script])

    context = %{data: %{"selected_pages" => [], "inspections" => []}, evidence: []}

    assert {:error, {:invalid_completion, :treatment_routes_not_honored}, _} =
             Strategy.generate(nil, request, context, %{inference: client}, force_json_text: true)
  end

  test "treatment validation requires tradeoffs and rejects a forbidden departure" do
    routes = [
      treatment_strategy("conceal", "revelation", "Keep the secret hidden.", false),
      treatment_strategy("volunteer", "relationship", "Offer the secret by choice.", false),
      treatment_strategy("accident", "action", "A mishap exposes the secret.", false)
    ]

    request = %{
      "alternatives" => 3,
      "options" => %{
        "treatments" =>
          Enum.map(routes, fn route ->
            %{
              "id" => route["treatment_id"],
              "mechanism_kind" => route["mechanism_kind"],
              "instruction" => route["dramatic_mechanism"]
            }
          end),
        "allow_brief_departure" => false
      }
    }

    context = %{data: %{"selected_pages" => [], "inspections" => []}, evidence: []}
    missing_tradeoff = List.update_at(routes, 0, &Map.put(&1, "tradeoffs", []))

    departed =
      List.update_at(
        routes,
        1,
        &Map.put(&1, "brief_departure", %{"departed" => true, "reason" => "Changes disclosure."})
      )

    for {invalid, reason} <- [
          {missing_tradeoff, :treatment_tradeoff_required},
          {departed, :brief_departure_not_permitted}
        ] do
      {:ok, script} = Agent.start_link(fn -> [fn _ -> %{"strategies" => invalid} end] end)
      client = Inference.Client.new!(adapter: ScriptedCompletion, adapter_opts: [script: script])

      assert {:error, {:invalid_completion, ^reason}, _} =
               Strategy.generate(nil, request, context, %{inference: client},
                 force_json_text: true,
                 decode_repairs: 0
               )

      Agent.stop(script)
    end
  end

  defp strategy_response do
    [
      treatment_strategy("conceal", "revelation", "Fold the evidence out of sight.", false),
      treatment_strategy("volunteer", "relationship", "Choose trust before being forced.", true),
      treatment_strategy("accident", "action", "Let handling the object expose the fact.", false)
    ]
  end

  defp treatment_strategy(id, kind, mechanism, departed) do
    %{
      "id" => id,
      "title" => String.capitalize(id),
      "premise_of_change" => mechanism,
      "dramatic_mechanism" => mechanism,
      "entry_state" => "Guarded",
      "exit_state" => "Changed",
      "beats" => [mechanism],
      "preserves" => ["wet paper map"],
      "changes" => [id],
      "inventions" => [],
      "consequences" => ["The next choice changes because this route happened."],
      "evidence_ids" => [],
      "open_questions" => [],
      "treatment_id" => id,
      "mechanism_kind" => kind,
      "tradeoffs" => ["This route gains one kind of pressure and gives up another."],
      "brief_departure" => %{
        "departed" => departed,
        "reason" =>
          if(departed,
            do: "Uses voluntary disclosure despite the initial concealment bias.",
            else: nil
          )
      }
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
          "id" => "route-#{strategy_id}",
          "title" => "Treatment #{strategy_id}",
          "reason" => "Materialize the requested dramatic mechanism as pages.",
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
