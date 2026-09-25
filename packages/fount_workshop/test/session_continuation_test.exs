Code.require_file("support/continuation_store.exs", __DIR__)
Code.require_file("support/scripted_completion.exs", __DIR__)

defmodule FountWorkshop.SessionContinuationTest do
  use ExUnit.Case, async: true
  alias FountWorkshop.TestSupport.{ContinuationStore, ScriptedCompletion}
  alias FountWorkshop.{Session, Store}

  test "partial materialization retains pages; resume skips saved branches and reuses inspected preparation" do
    model = Fount.Screenplay.new()
    {:ok, store} = ContinuationStore.start_link(model)

    {:ok, script} =
      Agent.start_link(fn ->
        [
          fn _ -> strategies() end,
          fn _ -> proposal(model, "a", "Mara blocks the closing door.") end,
          {:error, :temporary_failure}
        ]
      end)

    on_exit(fn ->
      Enum.each([store, script], fn pid ->
        try do
          Agent.stop(pid)
        catch
          :exit, {:noproc, _} -> :ok
        end
      end)
    end)

    client = Inference.Client.new!(adapter: ScriptedCompletion, adapter_opts: [script: script])
    services = %{store: %Store{repo: store, module: ContinuationStore}, inference: client}

    request = %{
      "version" => 1,
      "workflow" => "develop",
      "mode" => "revise",
      "base_revision_id" => model.revision.id,
      "instruction" => "A writer must stop a closing door without admitting why.",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "alternatives" => 2,
      "options" => %{"placement" => %{"kind" => "start"}}
    }

    assert {:error, :partial_workflow, first} = Session.start(model, request, services)
    assert first["progress"]["branches"]["a"]["status"] == "saved"
    assert first["progress"]["branches"]["b"]["status"] == "failed"
    first_id = first["progress"]["branches"]["a"]["candidate_id"]
    assert ContinuationStore.head(store).revision.id == model.revision.id

    Agent.update(script, fn [] ->
      [fn _ -> proposal(model, "b", "Mara wedges her shoe into the door.") end]
    end)

    assert {:ok, finished} = Session.resume(first["id"], services)
    assert finished["progress"]["branches"]["a"]["candidate_id"] == first_id
    assert finished["progress"]["branches"]["b"]["status"] == "saved"
    assert Agent.get(script, & &1) == []
    assert {:ok, session} = Session.get(first["id"], services)
    assert length(session["candidates"]) == 2
    texts = Enum.map(session["candidates"], &Fount.Screenplay.to_fountain(&1["screenplay"]))
    assert Enum.any?(texts, &String.contains?(&1, "blocks the closing door"))
    assert Enum.any?(texts, &String.contains?(&1, "wedges her shoe"))
    assert ContinuationStore.head(store).revision.id == model.revision.id
  end

  defp strategies do
    %{
      "strategies" =>
        Enum.map(["a", "b"], fn id ->
          %{
            "id" => id,
            "title" => id,
            "premise_of_change" => "Opposing the closure",
            "dramatic_mechanism" => "A visible choice",
            "entry_state" => "Outside",
            "exit_state" => "Inside",
            "beats" => ["Stop the door"],
            "preserves" => [],
            "changes" => [],
            "inventions" => [],
            "consequences" => [],
            "evidence_ids" => [],
            "open_questions" => []
          }
        end)
    }
  end

  defp proposal(model, strategy, text) do
    %{
      "version" => 1,
      "base_revision_id" => model.revision.id,
      "strategy_id" => strategy,
      "summary" => text,
      "inventions" => [],
      "unresolved_questions" => [],
      "groups" => [
        %{
          "id" => "opening",
          "title" => "Opening",
          "reason" => "A played choice",
          "depends_on" => [],
          "addresses_notes" => [],
          "evidence_ids" => [],
          "origin" => "generated_text",
          "operations" => [
            %{
              "kind" => "insert_scene",
              "value" => %{
                "after_scene_id" => nil,
                "scene" => %{
                  "local_id" => "new:opening",
                  "heading" => "INT. OFFICE - NIGHT",
                  "elements" => [
                    %{
                      "local_id" => "new:action",
                      "type" => "action",
                      "text" => text,
                      "attrs" => %{}
                    }
                  ]
                }
              }
            }
          ]
        }
      ]
    }
  end
end
