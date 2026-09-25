defmodule FountProbe.KnowledgeTrace.Behavior do
  @moduledoc "Checks whether selected behavior presupposes a belief unsupported by prior accessible material."
  alias FountProbe.{Access, Projection, Jev}

  def run(model, ids, subjects, proposition, clients, opts) do
    with {:ok, inputs, errors} <- prepare(model, ids, subjects, proposition, clients, opts),
         {:ok, result} <-
           Jev.evaluate(
             clients[:system_one],
             Enum.map(inputs, &Map.take(&1, ~w(id state))),
             [
               requires_belief:
                 SystemOneSDK.noul(
                   "Does this selected behavior require the subject already to believe the proposition? Judge the behavior, not whether the proposition is true."
                 ),
               prior_belief:
                 SystemOneSDK.noul(
                   "Does the supplied prior accessible material support this subject already believing the proposition? Exclude the selected behavior itself and later text."
                 )
             ],
             Keyword.put_new(opts, :profile_id, "knowledge_behavior")
           ) do
      by_id = Map.new(result["entries"], &{&1["input_id"], &1})
      thresholds = Jev.threshold_options(result["profile_asset"])
      supported = Keyword.get(thresholds, :supported, 0.8)
      unsupported = Keyword.get(thresholds, :unsupported, 0.2)

      rows =
        Enum.map(inputs, fn input ->
          answer = by_id[input["id"]]
          required = get_in(answer, ["answers", "requires_belief", "probability"])
          prior = get_in(answer, ["answers", "prior_belief", "probability"])
          complete = input["state"]["prior_state"]["complete_context"] == true

          assessment =
            cond do
              answer["status"] != "complete" or not is_number(required) or
                  not is_number(prior) ->
                "unknown"

              required >= supported and prior <= unsupported and complete ->
                "possible_knowledge_mismatch"

              not complete ->
                "unknown_access"

              true ->
                "no_supported_mismatch"
            end

          %{
            "subject" => input["subject"],
            "behavior_element_id" => input["behavior_element_id"],
            "point_before" => input["point_before"],
            "evidence_ids" => Enum.map(input["evidence"], & &1["evidence_id"]),
            "requires_belief" => get_in(answer, ["answers", "requires_belief"]),
            "prior_belief" => get_in(answer, ["answers", "prior_belief"]),
            "assessment" => assessment
          }
        end)

      {:ok,
       %{
         rows: rows,
         evidence: inputs |> Enum.flat_map(& &1["evidence"]) |> Enum.uniq_by(& &1["evidence_id"]),
         errors: errors,
         status:
           if(errors == [] and result["status"] == "complete", do: "complete", else: "partial"),
         provenance: result
       }}
    end
  end

  def prepare(model, ids, subjects, proposition, clients, opts) do
    Enum.reduce_while(ids, {:ok, [], []}, fn id, {:ok, inputs, errors} ->
      with {:ok, point} <- previous_point(model, id),
           {:ok, behavior} <-
             Projection.select(model, %{"targets" => [%{"kind" => "element", "id" => id}]}),
           true <- behavior != [] or {:error, :behavior_not_projected} do
        {next, next_errors} =
          Enum.map_reduce(subjects, errors, fn subject, errors ->
            projection =
              case subject["kind"] do
                "reader" -> "page_reader"
                "audience" -> "audience_estimate"
                "character" -> "character_access"
              end

            {ledger, errors} =
              if projection == "character_access" and
                   Keyword.get(opts, :access_mode, "evidence") == "evidence" do
                case Access.build(model, point, [subject["character_id"]], clients, opts) do
                  {:ok, ledger, _} ->
                    {ledger, errors}

                  _ ->
                    {[],
                     errors ++ [%{"code" => "behavior_access_incomplete", "element_id" => id}]}
                end
              else
                {[], errors}
              end

            view_opts =
              opts
              |> Keyword.put(:character_id, subject["character_id"])
              |> Keyword.put(:access_ledger, ledger)

            {:ok, state, evidence} = Projection.at(model, point, projection, view_opts)
            selected = hd(behavior)
            key = subject["character_id"] || subject["kind"]

            input = %{
              "id" => "behavior:#{id}:#{key}",
              "subject" => subject,
              "behavior_element_id" => id,
              "point_before" => point,
              "evidence" =>
                Enum.uniq_by(evidence ++ Projection.evidence(behavior), & &1["evidence_id"]),
              "state" => %{
                "subject" => subject,
                "proposition" => proposition,
                "prior_state" => state,
                "selected_behavior" =>
                  Map.take(selected, ~w(evidence_id excerpt target type text))
              }
            }

            {input, errors}
          end)

        {:cont, {:ok, inputs ++ next, next_errors}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp previous_point(model, id) do
    case Map.get(model.index.by_id, id) do
      nil ->
        {:error, :unknown_behavior_element}

      _ ->
        block = Fount.Query.block_for(model, id)
        first_id = if block, do: block.cue_id, else: id
        first_index = Enum.find_index(model.ir.elements, &(&1.id == first_id))

        prior =
          model.ir.scenes
          |> Enum.flat_map(fn scene ->
            {:ok, points} = Projection.points(model, scene.id)
            points
          end)
          |> Enum.filter(fn point ->
            case Projection.cutoff(model, point) do
              {:ok, n} -> n < first_index
              _ -> false
            end
          end)

        case List.last(prior) do
          nil -> {:error, :no_prior_observation_point}
          point -> {:ok, point}
        end
    end
  end
end
