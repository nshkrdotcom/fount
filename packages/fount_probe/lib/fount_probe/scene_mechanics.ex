defmodule FountProbe.SceneMechanics do
  @moduledoc "Descriptive scene functions and choices, not a universal score for a good scene."
  alias FountProbe.{Projection, Extraction, Jev, Report}

  @dimensions [
    problem: "Does a new problem become active?",
    decision: "Does a character make a consequential decision?",
    plan: "Does a plan change?",
    relationship: "Does a relationship change?",
    consequence: "Does an earlier choice have a consequence?",
    objective: "Does a character pursue a discernible objective?",
    information: "Does this scene disclose relevant information absent from the prior material?"
  ]
  def run(model, params, clients, opts \\ []) do
    with {:ok, units} <- Projection.select(model, params["selection"]),
         {:ok, extraction} <-
           Extraction.run(
             model,
             %{
               "selection" => params["selection"],
               "kinds" => ~w(goals events),
               "question" =>
                 params["concern"] ||
                   "Identify intentions, obstacles, choices and changes of tactic."
             },
             clients,
             opts
           ) do
      scenes = units |> Enum.map(& &1["scene_id"]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

      inputs =
        Enum.map(scenes, fn id ->
          {:ok, before, _} =
            Projection.at(model, %{"scene_id" => id, "through_element_id" => nil}, "page_reader")

          %{
            "id" => id,
            "state" => %{
              "scene" => Projection.compact(Enum.filter(units, &(&1["scene_id"] == id))),
              "prior" => before,
              "writer_objective" => params["objective"],
              "candidates" => Enum.filter(extraction.data["records"], &(&1["scene_id"] == id))
            }
          }
        end)

      questions =
        Enum.map(@dimensions, fn {key, question} ->
          {key,
           SystemOneSDK.noul(
             question <> " Judge the supplied material, not whether this function is required."
           )}
        end)

      questions =
        if params["include_tactics"] == true do
          options =
            extraction.data["records"]
            |> Enum.filter(&(&1["kind"] == "goals"))
            |> Enum.take(12)
            |> Enum.with_index()
            |> Enum.map(fn {r, i} -> {"tactic_#{i}", r["claim"]} end)

          if options == [],
            do: questions,
            else:
              questions ++
                [
                  tactic:
                    SystemOneSDK.choice(
                      "Which proposed objective or tactic most clearly organizes this scene?",
                      options ++ [{"other", "Other or unclear"}]
                    )
                ]
        else
          questions
        end

      with {:ok, result} <- Jev.evaluate(clients[:system_one], inputs, questions, opts) do
        {:ok,
         Report.new(model, "scene_mechanics", params, %{
           status:
             if(result["status"] == "complete" and extraction.status == "complete",
               do: "complete",
               else: "partial"
             ),
           data: %{"scenes" => result["entries"], "candidate_turns" => extraction.data["records"]},
           evidence: Projection.evidence(units),
           coverage: %{"scene_ids" => scenes},
           provenance: %{"evaluation" => result, "extraction" => extraction.provenance},
           errors: extraction.errors
         })}
      end
    end
  end
end
