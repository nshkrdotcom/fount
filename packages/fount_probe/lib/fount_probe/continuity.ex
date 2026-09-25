defmodule FountProbe.Continuity do
  @moduledoc "Evidence-linked state transitions with explicit chronology uncertainty."
  alias FountProbe.{Extraction, Projection, Jev, Report}

  def run(model, params, clients, opts \\ []) do
    with {:ok, extracted} <-
           Extraction.run(
             model,
             %{
               "selection" => params["selection"],
               "kinds" => ~w(props relationships timeline commitments),
               "question" =>
                 "Extract ownership, location, physical state, explicit time, promises and relationships; keep missing transitions uncertain."
             },
             clients,
             opts
           ),
         {:ok, units} <- Projection.select(model, params["selection"]) do
      evidence = Map.new(units, &{&1["evidence_id"], &1})
      order = Map.new(Enum.with_index(model.ir.scenes), fn {s, n} -> {s.id, n} end)

      chronology =
        model.authored_items
        |> Map.values()
        |> Enum.filter(&(&1["kind"] == "story_time" and &1["status"] == "active"))
        |> Map.new(&{&1["target"]["id"], &1["value"]["order"]})

      records =
        extracted.data["records"]
        |> Enum.filter(fn r ->
          Map.get(params, "subjects", []) == [] or
            Enum.any?(r["subjects"], &(&1 in params["subjects"]))
        end)

      known = records != [] and Enum.all?(records, &is_number(chronology[&1["scene_id"]]))
      rank = fn r -> if known, do: chronology[r["scene_id"]], else: order[r["scene_id"]] end

      by_subject =
        Enum.reduce(records, %{}, fn r, acc ->
          Enum.reduce(r["subjects"], acc, fn subject, acc ->
            Map.update(acc, subject, [r], &(&1 ++ [r]))
          end)
        end)

      pairs =
        Enum.flat_map(Enum.sort(by_subject), fn {subject, rs} ->
          rs
          |> Enum.sort_by(rank)
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.map(fn [a, b] -> {subject, a, b} end)
        end)

      inputs =
        Enum.with_index(pairs, fn {subject, a, b}, n ->
          %{
            "id" => "transition_#{n}",
            "state" => %{
              "subject" => subject,
              "earlier" => excerpts(a, evidence),
              "later" => excerpts(b, evidence),
              "chronology" =>
                if(known, do: "writer_declared_story_order", else: "reading_order_only")
            }
          }
        end)

      q =
        SystemOneSDK.choice(
          "How do these exact state observations relate? An unshown transfer or elapsed time may explain a change; heading differences alone are not contradictions.",
          contradiction: "Explicit states contradict",
          explained: "An explicit explanation supports the transition",
          unknown: "A transition or chronology is unestablished"
        )

      with {:ok, result} <-
             Jev.evaluate(
               clients[:system_one],
               inputs,
               [transition: q],
               Keyword.put_new(opts, :profile_id, "continuity")
             ) do
        rows =
          Enum.zip(pairs, result["entries"])
          |> Enum.map(fn {{subject, a, b}, r} ->
            %{
              "subject" => subject,
              "from" => a,
              "to" => b,
              "evidence_ids" => Enum.uniq(a["evidence_ids"] ++ b["evidence_ids"]),
              "assessment" => r["answers"]["transition"],
              "status" => r["status"],
              "repair_scene_id" => b["scene_id"]
            }
          end)

        {:ok,
         Report.new(model, "continuity", params, %{
           status:
             if(result["status"] == "complete" and extracted.status == "complete",
               do: "complete",
               else: "partial"
             ),
           data: %{
             "transitions" => rows,
             "chronology" => if(known, do: "writer_declared", else: "uncertain_reading_order"),
             "unresolved_subject_records" => Enum.filter(records, &(&1["subjects"] == []))
           },
           evidence: Projection.evidence(units),
           coverage: %{"transition_count" => length(pairs)},
           provenance: %{"extraction" => extracted.provenance, "evaluation" => result},
           errors: extracted.errors
         })}
      end
    end
  end

  defp excerpts(r, registry),
    do: %{"claim" => r["claim"], "material" => Enum.map(r["evidence_ids"], &registry[&1]["text"])}
end
