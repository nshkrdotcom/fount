defmodule Fount.Intelligence.Reporting.Renderer do
  @moduledoc "Deterministic reference rendering for writer result packets. No GUI assumptions are embedded here."

  alias Fount.Intelligence.Reporting.WriterPacket
  alias Fount.Writing.CanonicalJSON

  @spec render(WriterPacket.t(), :markdown | :json) :: {:ok, String.t()} | {:error, atom()}
  def render(%WriterPacket{} = packet, :json),
    do: {:ok, CanonicalJSON.encode!(WriterPacket.to_map(packet))}

  def render(%WriterPacket{} = packet, :markdown) do
    value = WriterPacket.to_map(packet)

    sections = [
      "# #{label(value["playbook"])}",
      "",
      "**Status:** #{value["status"]}",
      "**Source revision:** `#{value["source_revision"]}`",
      "",
      "## Writer concern",
      concern(value["concern"]),
      "",
      "## Intended experience and scope",
      bullets(%{"scope" => value["scope"], "intent" => value["intent"]}),
      "",
      "## Finding",
      value["finding"] || "No concise finding was produced.",
      "",
      "## Coverage",
      bullets(value["coverage"]),
      "",
      "## Evidence",
      evidence(value["evidence"]),
      "",
      "## Derived state",
      derived_state(value["derived_state"]),
      "",
      "## Trajectory",
      bullets(value["trajectory"]),
      "",
      "## Diagnoses",
      diagnoses(value["diagnoses"]),
      "",
      "## Abstentions",
      bullets(value["abstentions"]),
      "",
      "## Counterevidence and alternatives",
      evidence(value["counterevidence"]) <> "\n" <> bullets(value["alternatives"]),
      "",
      "## Uncertainty and missing evidence",
      bullets(value["uncertainty"] ++ value["missing_evidence"]),
      "",
      "## Protected strengths",
      bullets(value["protected_strengths"]),
      "",
      "## Next investigations",
      bullets(value["next_investigations"]),
      "",
      "## Strategies",
      bullets(value["strategies"]),
      "",
      "## Revision comparison",
      bullets(value["revision_comparison"] || []),
      "",
      "## Resource usage",
      resource_usage(value["resource_usage"]),
      "",
      "## Errors",
      bullets(value["errors"]),
      "",
      "## Limitations",
      bullets(value["limitations"])
    ]

    {:ok, Enum.join(sections, "\n") <> "\n"}
  end

  def render(_, _), do: {:error, :unsupported_writer_packet_render}

  defp concern(%{"statement" => statement} = concern) do
    desired = concern["desired_effect"]
    if is_binary(desired), do: statement <> "\n\nDesired effect: " <> desired, else: statement
  end

  defp concern(value), do: inspect(value)

  defp diagnoses([]), do: "- No diagnosis established from the available evidence."

  defp diagnoses(values) do
    Enum.map_join(values, "\n\n", fn diagnosis ->
      support = length(Map.get(diagnosis, "support", []))
      counter = length(Map.get(diagnosis, "counterevidence", []))

      "### " <>
        Map.get(diagnosis, "hypothesis", "Diagnosis") <>
        "\n" <>
        "- Uncertainty: " <>
        Map.get(diagnosis, "uncertainty", "unknown") <>
        "\n" <>
        "- Supporting evidence records: #{support}\n" <>
        "- Counterevidence records: #{counter}\n" <>
        "- Inspect source evidence: " <>
        Enum.map_join(Map.get(diagnosis, "support", []), ", ", &"`#{&1["id"]}`")
    end)
  end

  defp evidence([]), do: "- No source evidence was available."

  defp evidence(values) do
    Enum.map_join(values, "\n", fn item ->
      id = item["evidence_id"] || item["id"] || "evidence"
      excerpt = item["excerpt"] || ""
      "- `#{id}` — #{String.replace(excerpt, "\n", " ")}"
    end)
  end

  defp bullets(value) when is_map(value) do
    value
    |> Enum.sort_by(fn {key, _} -> to_string(key) end)
    |> Enum.map_join("\n", fn {key, item} -> "- #{key}: #{short(item)}" end)
  end

  defp bullets([]), do: "- None."
  defp bullets(values) when is_list(values), do: Enum.map_join(values, "\n", &("- " <> short(&1)))
  defp bullets(value), do: "- " <> short(value)

  defp short(value) when is_binary(value), do: value
  defp short(value), do: CanonicalJSON.encode!(value)

  defp derived_state(%{"base_reduction" => base, "first_pass_missing_evidence" => needs}) do
    "- Base relevance: #{short(base["counts"])}\n" <>
      "- Source evidence filtered: #{base["evidence_filtered"]}\n" <>
      "- Contextual evidence needs identified: #{length(needs)}"
  end

  defp derived_state(value), do: bullets(value)

  defp resource_usage(%{"preflight" => preflight, "actual" => actual}) do
    estimate = preflight["estimate"] || %{}
    base = get_in(actual, ["base", "actual"]) || %{}
    contextual = get_in(actual, ["contextual", "actual"]) || %{}
    budget = actual["analysis_budget"] || %{}

    [
      "- Preflight targets: #{reported(estimate["targets"], "unknown")}",
      "- Base acquired: #{reported(base["successful_states"], 0)}",
      "- Contextual acquired: #{reported(contextual["successful_states"], 0)}",
      "- Provider requests: #{reported(base["provider_requests"], 0) + reported(contextual["provider_requests"], 0)}",
      "- Cache hits: #{reported(base["cache_hits"], 0) + reported(contextual["cache_hits"], 0)}",
      "- Analysis budget: #{reported(budget["spent"], 0)} / #{reported(budget["limit"], "unknown")}",
      "- Hosted cost: #{reported(actual["hosted_cost"], "unknown")}"
    ]
    |> Enum.join("\n")
  end

  defp resource_usage(value), do: bullets(value)

  defp reported(nil, fallback), do: fallback
  defp reported(value, _fallback), do: value

  defp label(id),
    do:
      id |> String.replace("_", " ") |> String.split() |> Enum.map_join(" ", &String.capitalize/1)
end
