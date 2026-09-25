defmodule FountProbe.Action do
  @moduledoc "Action visibility and spatial description, with actual byte split sites and no invented printed density."
  alias FountProbe.{Projection, Jev, Report}

  def run(model, params, clients, opts \\ []) do
    with {:ok, units} <- Projection.select(model, params["selection"]) do
      action = Enum.filter(units, &(&1["type"] == "action"))

      inputs =
        Enum.map(
          action,
          &%{
            "id" => &1["evidence_id"],
            "state" => %{"passage" => &1["text"], "direction" => params["direction"]}
          }
        )

      qs = [
        visibility:
          SystemOneSDK.score(
            "How much of this action passage communicates visible behavior or audible events? This describes prose, not artistic quality.",
            [
              "Entirely explanatory interior information",
              "A small observable part amid explanation",
              "Observable events and explanation both carry the passage",
              "Mainly visible behavior or audible events"
            ]
          ),
        spatial:
          SystemOneSDK.noul(
            "Is the spatial relationship or sequence of physical actions unclear in this supplied passage?"
          ),
        camera: SystemOneSDK.noul("Does the passage explicitly instruct the camera or lens?"),
        interior:
          SystemOneSDK.noul(
            "Does the passage communicate private thought or explanation not shown by an observable action?"
          )
      ]

      with {:ok, result} <-
             Jev.evaluate(
               clients[:system_one],
               inputs,
               qs,
               Keyword.put_new(opts, :profile_id, "action")
             ) do
        splits =
          Enum.flat_map(action, fn u ->
            Regex.scan(~r/[.!?]\s+/u, u["excerpt"], return: :index)
            |> Enum.map(fn [{first, size}] ->
              %{
                "target" => u["target"],
                "after_byte" => u["target"]["span"]["byte_start"] + first + size,
                "evidence_ids" => [u["evidence_id"]],
                "status" => "possible_sentence_boundary_not_recommendation"
              }
            end)
          end)

        {:ok,
         Report.new(model, "action", params, %{
           status: result["status"],
           data: %{
             "paragraph_count" => length(Enum.uniq_by(action, & &1["target"]["id"])),
             "words" => Enum.sum(Enum.map(action, &length(String.split(&1["text"])))),
             "printed_lines" => nil,
             "layout_status" => "unavailable_without_measured_layout",
             "assessments" => result["entries"],
             "split_sites" => splits
           },
           evidence: Projection.evidence(action),
           provenance: result,
           coverage: %{"element_ids" => Enum.map(action, & &1["target"]["id"])}
         })}
      end
    end
  end
end
