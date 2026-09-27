defmodule Fount.Intelligence.Playbooks.Action do
  @moduledoc "Action visibility and spatial description, with actual byte split sites and no invented printed density."
  alias Fount.Intelligence.Acquisition.Measurements, as: Measurements
  alias Fount.Intelligence.Reporting.Report

  def run(model, params, clients, opts \\ []) do
    opts = Keyword.put(opts, :source_model, model)
    with {:ok, units} <- Fount.Selection.select(model, params["selection"]) do
      action = Enum.filter(units, &(&1["type"] == "action"))

      inputs =
        Enum.map(
          action,
          &%{
            "id" => &1["evidence_id"],
            "evidence" => Fount.Selection.evidence([&1]),
            "state" => %{"passage" => &1["text"], "direction" => params["direction"]}
          }
        )

      qs = [
        visibility:
          Fount.Observe.Question.score(
            "How much of this action passage communicates visible behavior or audible events? This describes prose, not artistic quality.",
            [
              "Entirely explanatory interior information",
              "A small observable part amid explanation",
              "Observable events and explanation both carry the passage",
              "Mainly visible behavior or audible events"
            ]
          ),
        spatial:
          Fount.Observe.Question.noul(
            "Is the spatial relationship or sequence of physical actions unclear in this supplied passage?"
          ),
        camera: Fount.Observe.Question.noul("Does the passage explicitly instruct the camera or lens?"),
        interior:
          Fount.Observe.Question.noul(
            "Does the passage communicate private thought or explanation not shown by an observable action?"
          )
      ]

      with {:ok, result} <-
             Measurements.evaluate(
               clients[:observe],
               inputs,
               qs,
               Keyword.put_new(opts, :lens_id, "action.visibility")
             ) do
        build_report(model, params, clients, opts, action, result)
      end
    end
  end

  defp build_report(model, params, clients, opts, action, result) do
    {layout, layout_errors} =
      case params["layout_report_id"] do
        nil ->
          {%{
             "printed_lines" => nil,
             "line_regions" => [],
             "layout_status" => "unavailable_without_measured_layout"
           }, []}

        id ->
          case measure_layout(clients[:layout],
                 model,
                 action,
                 id,
                 Keyword.get(opts, :report_reader)
               ) do
            {:ok, measured} ->
              {measured, []}

            {:error, reason} ->
              {%{
                 "printed_lines" => nil,
                 "line_regions" => [],
                 "layout_status" => "unavailable"
               }, [%{"code" => "layout_measurement_unavailable", "reason" => inspect(reason)}]}
          end
      end

    splits = Enum.flat_map(action, &sentence_splits/1)

    {:ok,
     Report.new(model, "action", params, %{
       status: if(layout_errors == [], do: result["status"], else: "partial"),
       data:
         Map.merge(
           %{
             "paragraph_count" => length(Enum.uniq_by(action, & &1["target"]["id"])),
             "words" => Enum.sum(Enum.map(action, &length(String.split(&1["text"])))),
             "assessments" => result["entries"],
             "split_sites" => splits
           },
           layout
         ),
       evidence: Fount.Selection.evidence(action),
       provenance: result,
       coverage: %{"element_ids" => Enum.map(action, & &1["target"]["id"])},
       errors: layout_errors
     })}
  end

  defp measure_layout(service, model, units, id, reader) when is_function(service, 4),
    do: service.(model, units, id, reader)
  defp measure_layout(_, _, _, _, _), do: {:error, :missing_layout_service}

  defp sentence_splits(unit) do
    Regex.scan(~r/[.!?]\s+/u, unit["excerpt"], return: :index)
    |> Enum.map(fn [{first, size}] ->
      %{
        "target" => unit["target"],
        "after_byte" => unit["target"]["span"]["byte_start"] + first + size,
        "evidence_ids" => [unit["evidence_id"]],
        "status" => "possible_sentence_boundary_not_recommendation"
      }
    end)
  end
end
