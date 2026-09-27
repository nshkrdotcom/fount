defmodule Fount.Intelligence.Acquisition.Planner do
  @moduledoc "Plans source-grounded Phase-5 diagnosis passes without acquiring evidence."

  alias Fount.Intelligence.Diagnosis.Concern
  alias Fount.Writing.CanonicalJSON

  @default_max_evidence 48

  @spec plan(Fount.Screenplay.t(), map(), keyword()) :: {:ok, map()} | {:error, atom()}
  def plan(model, request, opts \\ [])

  def plan(%Fount.Screenplay{} = model, request, opts) when is_map(request) and is_list(opts) do
    with true <- Keyword.keyword?(opts),
         {:ok, concern} <- Concern.new(request["concern"] || request[:concern]),
         {:ok, evidence, evidence_scope} <- evidence(model, request, opts),
         {:ok, hypotheses} <- hypotheses(request, evidence),
         true <- hypotheses != [] do
      base_inputs =
        Enum.map(evidence, fn source ->
          %{
            "id" => "base:" <> source["evidence_id"],
            "state" => %{
              "concern" => Concern.to_map(concern),
              "evidence" => %{
                "id" => source["evidence_id"],
                "excerpt" => source["excerpt"],
                "target" => source["target"]
              }
            },
            "target" => source["target"],
            "evidence" => [source]
          }
        end)

      {:ok,
       %{
         "concern" => concern,
         "evidence" => evidence,
         "evidence_scope" => evidence_scope,
         "hypotheses" => hypotheses,
         "base_inputs" => base_inputs,
         "selection" => request["selection"] || request[:selection] || %{"whole_screenplay" => true},
         "intent" => request["intent"] || request[:intent] || %{},
         "strategies" => request["strategies"] || request[:strategies] || [],
         "revision_comparison" => request["revision_comparison"] || request[:revision_comparison],
         "source_revision" => model.revision.id
       }}
    else
      false -> {:error, :invalid_playbook_request}
      {:error, _} = error -> error
      _ -> {:error, :invalid_playbook_request}
    end
  rescue
    _ -> {:error, :invalid_playbook_request}
  end

  def plan(_, _, _), do: {:error, :invalid_playbook_request}

  defp evidence(model, request, opts) do
    selection = request["selection"] || request[:selection] || %{"whole_screenplay" => true}
    limit = Keyword.get(opts, :max_evidence_fragments, @default_max_evidence)

    with true <- is_integer(limit) and limit > 0 and limit <= 500,
         {:ok, units} <- Fount.Selection.select(model, selection) do
      all = Fount.Selection.evidence(units)
      requested_ids = request["evidence_ids"] || request[:evidence_ids]

      explicit? = is_list(requested_ids) and requested_ids != []

      selected =
        if explicit? do
          index = Map.new(all, &{&1["evidence_id"], &1})
          Enum.map(requested_ids, &Map.get(index, &1))
        else
          Enum.take(all, limit)
        end

      valid =
        selected != [] and length(selected) <= limit and Enum.all?(selected, &is_map/1) and
          length(Enum.uniq_by(selected, & &1["evidence_id"])) == length(selected)

      if valid do
        {:ok, selected,
         %{
           "available_fragments" => length(all),
           "selected_fragments" => length(selected),
           "explicit_evidence_ids" => explicit?,
           "truncated_by_host_limit" => not explicit? and length(all) > length(selected),
           "max_evidence_fragments" => limit
         }}
      else
        {:error, :missing_or_excess_source_evidence}
      end
    else
      _ -> {:error, :invalid_selection}
    end
  end

  defp hypotheses(request, evidence) do
    values = request["hypotheses"] || request[:hypotheses]
    evidence_ids = Enum.map(evidence, & &1["evidence_id"])

    if is_list(values) and values != [] do
      normalized =
        Enum.map(values, fn value ->
          value = stringify(value)
          ids = if value["evidence_ids"] in [nil, []], do: evidence_ids, else: value["evidence_ids"]
          value = Map.put(value, "evidence_ids", ids)
          id =
            value["id"] ||
              "hypothesis-" <>
                String.slice(
                  CanonicalJSON.hash(%{
                    "code" => value["code"] || "writer_hypothesis",
                    "hypothesis" => value["hypothesis"],
                    "evidence_ids" => ids
                  }),
                  0,
                  24
                )
          Map.put(value, "id", id)
        end)

      selected = MapSet.new(evidence_ids)

      if Enum.all?(normalized, fn hypothesis ->
           valid_hypothesis?(hypothesis) and
             Enum.all?(hypothesis["evidence_ids"], &MapSet.member?(selected, &1))
         end),
        do: {:ok, normalized},
        else: {:error, :invalid_hypotheses}
    else
      {:error, :hypotheses_required}
    end
  end

  defp valid_hypothesis?(value) do
    is_map(value) and is_binary(value["hypothesis"]) and String.trim(value["hypothesis"]) != "" and
      is_list(value["evidence_ids"]) and value["evidence_ids"] != [] and
      Enum.all?(value["evidence_ids"], &is_binary/1) and
      length(value["evidence_ids"]) == length(Enum.uniq(value["evidence_ids"])) and
      (is_nil(value["context"]) or is_map(value["context"]))
  end

  defp stringify(value) when is_map(value) do
    Map.new(value, fn
      {key, item} when is_atom(key) -> {Atom.to_string(key), stringify_value(item)}
      {key, item} -> {key, stringify_value(item)}
    end)
  end

  defp stringify(_), do: %{}
  defp stringify_value(value) when is_map(value), do: stringify(value)
  defp stringify_value(value) when is_list(value), do: Enum.map(value, &stringify_value/1)
  defp stringify_value(value), do: value
end
