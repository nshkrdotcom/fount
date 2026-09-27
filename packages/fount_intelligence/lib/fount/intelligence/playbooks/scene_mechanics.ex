defmodule Fount.Intelligence.Playbooks.SceneMechanics do
  @moduledoc "Descriptive scene functions and choices, not a universal score for a good scene."
  alias Fount.Intelligence.Acquisition.Extraction
  alias Fount.Intelligence.Acquisition.Measurements, as: Measurements
  alias Fount.Intelligence.Reporting.Report
  alias Fount.Observe.Projection
  alias Fount.Observe.Question

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
    opts = Keyword.put(opts, :source_model, model)

    with {:ok, units} <- Fount.Selection.select(model, params["selection"]),
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
          {:ok, before, prior_evidence} =
            Projection.at(model, %{"scene_id" => id, "through_element_id" => nil}, "page_reader")

          %{
            "id" => id,
            "evidence" =>
              Enum.uniq_by(
                prior_evidence ++
                  Fount.Selection.evidence(Enum.filter(units, &(&1["scene_id"] == id))),
                & &1["evidence_id"]
              ),
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
           Question.noul(
             question <> " Judge the supplied material, not whether this function is required."
           )}
        end)

      questions = maybe_tactic_questions(questions, params, extraction)

      with {:ok, result} <- Measurements.evaluate(clients[:observe], inputs, questions, opts) do
        {:ok,
         Report.new(model, "scene_mechanics", params, %{
           status:
             if(result["status"] == "complete" and extraction.status == "complete",
               do: "complete",
               else: "partial"
             ),
           data: %{"scenes" => result["entries"], "candidate_turns" => extraction.data["records"]},
           evidence:
             Enum.uniq_by(
               Fount.Selection.evidence(units) ++ Enum.flat_map(inputs, & &1["evidence"]),
               & &1["evidence_id"]
             ),
           coverage: %{"scene_ids" => scenes},
           provenance: %{"evaluation" => result, "extraction" => extraction.provenance},
           errors: extraction.errors
         })}
      end
    end
  end

  defp maybe_tactic_questions(questions, %{"include_tactics" => true}, extraction) do
    options =
      extraction.data["records"]
      |> Enum.filter(&(&1["kind"] == "goals"))
      |> Enum.take(12)
      |> Enum.with_index()
      |> Enum.map(fn {record, index} -> {"tactic_#{index}", record["claim"]} end)

    if options == [] do
      questions
    else
      questions ++
        [
          tactic:
            Question.choice(
              "Which proposed objective or tactic most clearly organizes this scene?",
              options ++ [{"other", "Other or unclear"}]
            )
        ]
    end
  end

  defp maybe_tactic_questions(questions, _, _), do: questions
end
