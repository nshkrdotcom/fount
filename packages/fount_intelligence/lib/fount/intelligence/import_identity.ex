defmodule Fount.Intelligence.ImportIdentity do
  @moduledoc "Deterministic same-revision identity support, independent of response ordering and labels."

  def support_set(kind, occurrences, spans) do
    occurrences
    |> Enum.flat_map(fn occurrence ->
      Enum.map(occurrence["evidence"] || [], fn evidence ->
        absolute = absolute_evidence(evidence, spans)

        [
          kind,
          occurrence["role"],
          absolute["byte_start"],
          absolute["byte_end"],
          occurrence["literal_element_id"]
        ]
      end)
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def handle(assessment, entity, occurrences, spans) do
    occurrences =
      if occurrences == [],
        do: [%{"role" => "unknown", "evidence" => entity["evidence"]}],
        else: occurrences

    support = support_set(entity["kind"], occurrences, spans)
    fingerprint = support |> Jason.encode!() |> Fount.ID.hash()

    Fount.ID.v5(assessment["project_id"], [
      "semantic-identity:",
      assessment["revision_id"],
      ":",
      entity["kind"],
      ":",
      fingerprint
    ])
  end

  def absolute_evidence(evidence, spans) do
    span = Map.fetch!(spans, evidence["span_id"])

    %{
      "byte_start" => span["byte_start"] + evidence["byte_start"],
      "byte_end" => span["byte_start"] + evidence["byte_end"],
      "quote" => evidence["quote"]
    }
  end
end
