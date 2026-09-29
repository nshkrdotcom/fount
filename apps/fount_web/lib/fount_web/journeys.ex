defmodule FountWeb.Journeys do
  @moduledoc "Deterministic Phase 06 screenplay journeys. Runtime acceptance still exercises real Core/Run/Workshop persistence."
  alias Fount.Query
  alias Fount.Writing.Principal

  @journeys ~w(opening reveal dialogue)
  def names, do: @journeys

  def fixture_fountain do
    """
    Title: Phase 06 Rights-Cleared Demo
    Author: Fount Fixture

    INT. KITCHEN - MORNING

    MARA sets an unopened envelope beside the coffee maker.

    MARA
    I said I would wait.

    EXT. TRAIN PLATFORM - NIGHT

    NORA waits under the departure board, one hand around a brass key.

    NORA
    The train is late.

    OWEN
    That's what you wanted.

    INT. INTERVIEW ROOM - LATER

    Nora keeps her hands flat on the table.

    NORA
    I didn't miss anything.
    """
  end

  def configuration(root, journey, owner_id) when journey in @journeys do
    owner = principal(:human, owner_id)
    service = FountWeb.Actors.principal(:service)

    {workflow, selection, instruction, protected, completion, approver} =
      case journey do
        "opening" ->
          {"develop", %{"whole_screenplay" => true},
           "JOURNEY:opening Open on a visible choice that creates an immediate consequence.", [],
           "candidate", nil}

        "reveal" ->
          protected_element =
            root.ir.elements
            |> Enum.find(fn element ->
              element.type == :action and String.contains?(element.text, "departure board")
            end)
            |> then(
              &(&1 || Enum.find(root.ir.elements, fn element -> element.type == :action end))
            )

          scene = Query.scene_for(root, protected_element.id)

          late_action =
            Enum.find(root.ir.elements, fn element ->
              element.type == :action and String.contains?(element.text, "hands flat")
            end)

          marker =
            "JOURNEY:reveal TARGET_PROTECTED:#{protected_element.id} TARGET_LATE_ACTION:#{late_action.id} AFTER_SCENE:#{scene.id}"

          protected = [%{"element_id" => protected_element.id, "text" => protected_element.text}]

          {"propagate", %{"whole_screenplay" => true},
           marker <>
             " Move the theft revelation late while preserving the train-platform beat and repair its consequence.",
           protected, "accept", Principal.to_map(owner)}

        "dialogue" ->
          dialogue =
            Enum.find(root.ir.elements, fn element ->
              element.type == :dialogue and String.contains?(element.text, "didn't miss")
            end)

          scene = Query.scene_for(root, dialogue.id)
          marker = "JOURNEY:dialogue TARGET_DIALOGUE:#{dialogue.id}"

          {"pass", %{"targets" => [%{"kind" => "scene", "id" => scene.id}]},
           marker <>
             " Sharpen only the selected scene's dialogue; preserve out-of-scope action and protected lines.",
           [], "accept", Principal.to_map(service)}
      end

    policy = %{
      "gates" => %{
        "investigation_scope" => "automatic",
        "strategy_choice" => "human",
        "candidate_generation" => "automatic",
        "iteration" => "automatic"
      },
      "completion" => completion,
      "approver" => approver,
      "fallback_approver" => if(journey == "dialogue", do: Principal.to_map(owner), else: nil),
      "route_choice" => %{"rule" => "pause_on_material_tradeoff"},
      "limits" => %{
        "max_iterations" => 1,
        "max_malformed_repairs_per_call" => 1,
        "max_transient_retries" => 2,
        "max_inference_calls" => 24,
        "max_measurement_states" => 500,
        "money" => nil
      }
    }

    request = %{
      "version" => 1,
      "workflow" => workflow,
      "mode" => "revise",
      "base_revision_id" => root.revision.id,
      "instruction" => instruction,
      "selection" => selection,
      "constraints" => [],
      "alternatives" => 1,
      "options" => options(workflow)
    }

    %{workflow: workflow, request: request, protected_material: protected, policy: policy}
  end

  defp options("develop"), do: %{"placement" => %{"kind" => "start"}}
  defp options("pass"), do: %{"profile" => "dialogue_subtext"}

  defp options("propagate"),
    do: %{
      "change" => "Delay the theft revelation until the final scene",
      "intended_effect" => "Delay knowledge and repair downstream behavior"
    }

  defp options(_), do: %{}

  defp principal(type, id) do
    {:ok, principal} = Principal.new(type, id)
    principal
  end
end
