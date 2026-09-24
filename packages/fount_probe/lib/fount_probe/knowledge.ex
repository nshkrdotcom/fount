defmodule FountProbe.Knowledge do
  @moduledoc "Jev assisted reveal checks over exact, isolated screenplay perspectives."

  alias FountProbe.State

  @question SystemOneSDK.noul(
              "Based only on the included on-screen material, is there enough evidence to infer the proposition? " <>
                "Treat absence of evidence as uncertainty. Do not use later scenes, notes, or boneyards."
            )

  @doc "Evaluates audience and confirmed-speaker views before one scene."
  def trace(model, proposition, before_scene_id, character_ids, client)
      when is_binary(proposition) and is_list(character_ids) do
    with {:ok, audience} <- State.audience_before(model, before_scene_id),
         {:ok, views} <- character_views(model, character_ids, before_scene_id) do
      assessments =
        [{"audience", audience} | views]
        |> Enum.map(fn {name, view} -> {name, evaluate_view(client, view, proposition)} end)
        |> Map.new()

      status =
        if Enum.all?(assessments, fn {_, result} -> result.status in [:complete, :unknown] end),
          do: :complete,
          else: :partial

      {:ok,
       %{
         screenplay_id: model.id,
         revision_id: model.revision.id,
         before_scene_id: before_scene_id,
         proposition: proposition,
         status: status,
         assessments: assessments
       }}
    end
  end

  def trace(_, _, _, _, _), do: {:error, :invalid_trace_request}

  defp character_views(model, ids, scene_id) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      case State.speaker_before(model, id, scene_id) do
        {:ok, view} -> {:cont, {:ok, [{id, view} | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp evaluate_view(_client, %{"scenes" => []} = view, _proposition),
    do: %{
      status: :unknown,
      reason: :no_visible_scenes,
      scene_ids: view["scene_ids"],
      evidence_ids: []
    }

  defp evaluate_view(client, view, proposition) do
    state = %{
      "proposition" => proposition,
      "perspective" => view["perspective"],
      "scenes" => view["scenes"]
    }

    evidence_ids = for scene <- view["scenes"], element <- scene["elements"], do: element["id"]

    case SystemOneSDK.evaluate(client, state, q: @question) do
      {:ok, response} ->
        case response.answers[:q] do
          %{noul: probability} when is_number(probability) ->
            %{
              status: :complete,
              probability: probability,
              scene_ids: view["scene_ids"],
              evidence_ids: evidence_ids,
              model: response.model,
              prepared_fingerprint: response.prepared_fingerprint
            }

          _ ->
            %{
              status: :error,
              reason: :missing_answer,
              scene_ids: view["scene_ids"],
              evidence_ids: evidence_ids
            }
        end

      {:error, error} ->
        %{status: :error, reason: error, scene_ids: view["scene_ids"], evidence_ids: evidence_ids}
    end
  end
end
