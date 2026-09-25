defmodule FountProbe.KnowledgeTrace do
  @moduledoc "Exhaustive requested prefix checks with distinct establishment, inference, belief and suspicion questions."
  alias FountProbe.{Access, Projection, Jev, Report}
  alias FountProbe.Writing.DecisionPolicy

  def run(model, params, clients, opts \\ []) do
    with :ok <- validate_points(model, params["points"]),
         :ok <- validate_subjects(model, params["subjects"]) do
      character_ids =
        for %{"kind" => "character", "character_id" => id} <- params["subjects"], do: id

      contexts =
        Enum.with_index(params["points"], fn point, index ->
          access =
            if character_ids != [] and Map.get(params, "access_mode", "evidence") == "evidence" do
              Access.build(model, point, character_ids, clients, opts)
            else
              {:ok, [], %{}}
            end

          {ledger, access_trace, access_error} =
            case access do
              {:ok, ledger, trace} -> {ledger, trace, nil}
              {:error, reason, _} -> {[], %{}, inspect(reason)}
              {:error, reason} -> {[], %{}, inspect(reason)}
            end

          entries =
            Enum.map(params["subjects"], fn subject ->
              projection =
                case subject["kind"] do
                  "audience" -> "audience_estimate"
                  "reader" -> "page_reader"
                  "character" -> "character_access"
                end

              view_opts =
                opts
                |> Keyword.put(:character_id, subject["character_id"])
                |> Keyword.put(:access_ledger, ledger)
                |> Keyword.put(:access_mode, Map.get(params, "access_mode", "evidence"))

              {:ok, state, evidence} = Projection.at(model, point, projection, view_opts)
              id = subject_key(subject) <> ":#{index}"

              %{
                "id" => id,
                "subject" => subject,
                "point" => point,
                "state" => Map.put(state, "proposition", params["proposition"]),
                "evidence" => evidence
              }
            end)

          %{
            entries: entries,
            ledger: ledger,
            access_trace: access_trace,
            access_error: access_error
          }
        end)

      entries = Enum.flat_map(contexts, & &1.entries)

      questions = [
        established:
          SystemOneSDK.noul(
            "Does the accessible evidence establish the positive proposition? A statement may be a lie; intentions are not established facts."
          ),
        could_infer:
          SystemOneSDK.noul(
            "Could this subject reasonably infer the proposition from this accessible material? Do not use outside or later information."
          ),
        believes:
          SystemOneSDK.noul(
            "Does the accessible material support this subject believing the proposition? Belief and truth are separate; for a reader/audience assess the invited belief."
          )
      ]

      questions =
        if params["suspicion"] == true,
          do:
            questions ++
              [
                suspicion:
                  SystemOneSDK.score(
                    "How much does the accessible material invite suspicion of the proposition?",
                    [
                      "No supporting indication",
                      "A possibility with little support",
                      "Plausible among alternatives",
                      "Strong apparent support",
                      "Apparently conclusive here"
                    ]
                  )
              ],
          else: questions

      with {:ok, result} <-
             Jev.evaluate(
               clients[:system_one],
               Enum.map(entries, &Map.take(&1, ~w(id state))),
               questions,
               Keyword.put_new(opts, :profile_id, "knowledge_trace")
             ) do
        policy_opts = Jev.threshold_options(result["profile_asset"])
        reveal_threshold = Keyword.get(policy_opts, :supported, 0.8)
        by_id = Map.new(result["entries"], &{&1["input_id"], &1})

        rows =
          Enum.map(entries, fn entry ->
            answer = by_id[entry["id"]]

            answers =
              Map.new(answer["answers"], fn {key, value} ->
                value =
                  if value["type"] == "noul" and is_number(value["probability"]) do
                    {:ok, policy} =
                      DecisionPolicy.noul(
                        value["probability"],
                        Keyword.put(
                          policy_opts,
                          :complete_context,
                          entry["state"]["complete_context"]
                        )
                      )

                    Map.merge(value, policy)
                  else
                    value
                  end

                {key, value}
              end)

            %{
              "subject" => entry["subject"],
              "point" => entry["point"],
              "status" => answer["status"],
              "answers" => answers,
              "evidence_ids" => Enum.map(entry["evidence"], & &1["evidence_id"]),
              "coverage" =>
                Map.take(entry["state"], ~w(complete_context access_coverage projection_gaps))
            }
          end)

        curves =
          Map.new(params["subjects"], fn subject ->
            curve =
              rows
              |> Enum.filter(&(&1["subject"] == subject))
              |> Enum.map(
                &%{
                  "point" => &1["point"],
                  "probability" => get_in(&1, ["answers", "established", "probability"])
                }
              )

            {:ok, boundary} = DecisionPolicy.boundary(curve, reveal_threshold)
            {subject_key(subject), boundary}
          end)

        access_errors =
          Enum.flat_map(contexts, fn c ->
            if c.access_error,
              do: [%{"code" => "access_incomplete", "message" => c.access_error}],
              else: []
          end)

        behavior =
          case params["behavior_element_ids"] || [] do
            [] ->
              %{rows: [], evidence: [], errors: [], status: "complete", provenance: %{}}

            ids ->
              case FountProbe.KnowledgeTrace.Behavior.run(
                     model,
                     ids,
                     params["subjects"],
                     params["proposition"],
                     clients,
                     opts
                   ) do
                {:ok, result} ->
                  result

                {:error, reason} ->
                  %{
                    rows: [],
                    evidence: [],
                    errors: [
                      %{"code" => "behavior_check_unavailable", "reason" => inspect(reason)}
                    ],
                    status: "partial",
                    provenance: %{}
                  }
              end
          end

        {:ok,
         Report.new(model, "knowledge_trace", params, %{
           status:
             if(
               result["status"] == "complete" and access_errors == [] and
                 behavior.status == "complete",
               do: "complete",
               else: "partial"
             ),
           data: %{
             "rows" => rows,
             "curves" => curves,
             "knowledge_gaps" => gaps(rows),
             "behavior_checks" => behavior.rows,
             "access_ledger" => Enum.flat_map(contexts, & &1.ledger),
             "intended_reveal_point" => params["intended_reveal_point"],
             "reveal_comparison" =>
               if(params["intended_reveal_point"],
                 do: assess_reveal(model, curves, params["intended_reveal_point"]),
                 else: nil
               )
           },
           evidence:
             (Enum.flat_map(entries, & &1["evidence"]) ++ behavior.evidence)
             |> Enum.uniq_by(& &1["evidence_id"]),
           coverage: %{"points" => params["points"], "subjects" => params["subjects"]},
           errors: access_errors ++ behavior.errors,
           provenance: %{
             "evaluation" => result,
             "access" => Enum.map(contexts, & &1.access_trace),
             "behavior" => behavior.provenance
           }
         })}
      end
    end
  end

  def locate(model, params, clients, opts \\ []) do
    with {:ok, points} <- Projection.points(model, params["scene_id"]) do
      subject =
        case params["projection"] do
          "page_reader" -> %{"kind" => "reader"}
          "audience_estimate" -> %{"kind" => "audience"}
          "character_access" -> %{"kind" => "character", "character_id" => params["character_id"]}
        end

      request = %{
        "proposition" => params["proposition"],
        "subjects" => [subject],
        "points" => points,
        "threshold" => Map.get(params, "threshold", 0.8)
      }

      with {:ok, report} <-
             run(
               model,
               request,
               clients,
               Keyword.put(
                 opts,
                 :include_prior_context,
                 Map.get(params, "include_prior_context", true)
               )
             ) do
        {:ok, %{report | tool: "locate_boundary", request: params}}
      end
    end
  end

  @doc "Compares supported observation points with a writer-declared reveal point."
  def assess_reveal(model, curves, intended_point) do
    {:ok, intended_index} = Projection.cutoff(model, intended_point)

    Map.new(curves, fn {subject, boundary} ->
      first =
        if boundary["status"] == "already_supported_at_entry",
          do: get_in(boundary, ["curve", Elixir.Access.at(0), "point"]),
          else: boundary["first_crossing"]

      assessment =
        cond do
          boundary["status"] == "incomplete" ->
            %{"status" => "unknown", "reason" => "incomplete_curve"}

          is_nil(first) ->
            %{"status" => "not_observed_in_checked_points"}

          true ->
            {:ok, observed_index} = Projection.cutoff(model, first)

            status =
              cond do
                observed_index < intended_index -> "observed_before_intended"
                observed_index == intended_index -> "at_intended"
                true -> "observed_after_intended"
              end

            %{"status" => status, "observed_point" => first}
        end

      {subject, assessment}
    end)
  end

  defp validate_points(model, points) when is_list(points) and points != [] do
    if Enum.all?(points, &match?({:ok, _}, Projection.cutoff(model, &1))),
      do: :ok,
      else: {:error, :invalid_points}
  end

  defp validate_points(_, _), do: {:error, :empty_points}

  defp validate_subjects(model, subjects) when is_list(subjects) and subjects != [] do
    ok =
      Enum.all?(subjects, fn s ->
        s["kind"] in ["audience", "reader"] or
          (s["kind"] == "character" and Map.has_key?(model.cast, s["character_id"]))
      end)

    if ok and length(Enum.uniq(subjects)) == length(subjects),
      do: :ok,
      else: {:error, :invalid_subjects}
  end

  defp validate_subjects(_, _), do: {:error, :empty_subjects}
  defp subject_key(%{"kind" => "character", "character_id" => id}), do: id
  defp subject_key(%{"kind" => kind}), do: kind

  defp gaps(rows) do
    audience =
      Map.new(
        Enum.filter(rows, &(&1["subject"]["kind"] == "audience")),
        &{&1["point"], get_in(&1, ["answers", "established", "probability"])}
      )

    Enum.flat_map(rows, fn row ->
      a = audience[row["point"]]
      b = get_in(row, ["answers", "established", "probability"])

      if row["subject"]["kind"] == "character" and is_number(a) and is_number(b),
        do: [
          %{
            "subject" => row["subject"],
            "point" => row["point"],
            "audience_minus_character" => a - b
          }
        ],
        else: []
    end)
  end
end
