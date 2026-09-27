defmodule Fount.Intelligence.Acquisition.Knowledge do
  @moduledoc "Reveal checks over exact prior on-screen perspectives; empty access remains unknown."
  alias Fount.Intelligence.Acquisition.{Measurements, Views}
  alias Fount.Observe.Question

  def trace(model, proposition, before_scene_id, character_ids, provider)
      when is_binary(proposition) and is_list(character_ids) do
    with {:ok, audience} <- Views.audience_before(model, before_scene_id),
         {:ok, characters} <- character_views(model, character_ids, before_scene_id) do
      evaluate_views(model, proposition, before_scene_id, provider, [
        {"audience", audience} | characters
      ])
    end
  end

  def trace(_, _, _, _, _), do: {:error, :invalid_trace_request}

  defp evaluate_views(model, proposition, before_scene_id, provider, views) do
    inputs =
      for {name, view} <- views,
          view["scenes"] != [],
          do: %{
            "id" => name,
            "state" => %{
              "proposition" => proposition,
              "perspective" => view["perspective"],
              "scenes" => view["scenes"],
              "material" => view["material"]
            }
          }

    question =
      Question.noul(
        "Based only on the included on-screen material, is there enough evidence to infer the proposition? Treat absence of evidence as uncertainty. Do not use later scenes, notes, or boneyards."
      )

    with {:ok, result} <-
           Measurements.evaluate(provider, inputs, [q: question], source_model: model) do
      results = Map.new(result["entries"], &{&1["input_id"], &1})

      assessments =
        Map.new(views, fn {name, view} -> {name, assessment(view, results[name])} end)

      {:ok,
       %{
         screenplay_id: model.id,
         revision_id: model.revision.id,
         before_scene_id: before_scene_id,
         proposition: proposition,
         status: if(result["status"] == "complete", do: :complete, else: :partial),
         assessments: assessments,
         acquisition: result
       }}
    end
  end

  defp character_views(model, ids, scene_id) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      case Views.speaker_before(model, id, scene_id) do
        {:ok, view} -> {:cont, {:ok, acc ++ [{id, view}]}}
        error -> {:halt, error}
      end
    end)
  end

  defp assessment(%{"scenes" => []} = view, _),
    do: %{
      status: :unknown,
      reason: :no_visible_scenes,
      scene_ids: view["scene_ids"],
      evidence_ids: []
    }

  defp assessment(view, result) do
    evidence_ids = for scene <- view["scenes"], element <- scene["elements"], do: element["id"]
    probability = get_in(result, ["answers", "q", "probability"])

    if is_number(probability),
      do: %{
        status: :complete,
        probability: probability,
        scene_ids: view["scene_ids"],
        evidence_ids: evidence_ids
      },
      else: %{
        status: :error,
        reason: :measurement_unavailable,
        scene_ids: view["scene_ids"],
        evidence_ids: evidence_ids
      }
  end
end
