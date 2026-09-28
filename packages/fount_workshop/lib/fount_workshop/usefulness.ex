defmodule FountWorkshop.Usefulness do
  @moduledoc """
  Evidence records for writer usefulness without turning screenplay craft into a score.

  Records keep engineering behavior separate from writer response. A writer
  keeping the original is a valid outcome, and reports never rank the workflow
  conditions or infer an overall screenplay-quality number.
  """

  @conditions ~w(human_only basic_llm fount_assisted)
  @outcomes ~w(positive neutral negative)
  @dimensions ~w(task_completion next_decision agency voice_retention alternative_diversity consequence_usefulness rejection_time_ms)

  @doc "Conditions retained for comparative evaluation; no condition is declared a winner."
  def conditions, do: @conditions

  @doc "Builds one explicit task record from observed engineering data and a supplied human response."
  @spec record(map()) :: {:ok, map()} | {:error, term()}
  def record(attrs) when is_map(attrs) do
    with {:ok, task_id} <- required_string(attrs, "task_id"),
         {:ok, condition} <- member(attrs, "condition", @conditions),
         {:ok, outcome} <- member(attrs, "outcome", @outcomes),
         {:ok, kept_original} <- required_boolean(attrs, "kept_original"),
         {:ok, engineering} <- engineering(attrs["engineering"] || %{}),
         {:ok, response} <- human_response(attrs, outcome, kept_original) do
      {:ok,
       %{
         "version" => 1,
         "task_id" => task_id,
         "condition" => condition,
         "output_refs" => list(attrs["output_refs"]),
         "engineering" => engineering,
         "human_response" => response
       }}
    end
  end

  def record(_), do: {:error, :invalid_usefulness_record}

  @doc "Returns the supplied records without scoring, ordering, or choosing a winning condition."
  @spec report([map()], keyword()) :: {:ok, map()} | {:error, term()}
  def report(records, opts \\ [])

  def report(records, opts) when is_list(records) do
    with :ok <- validate_records(records) do
      {:ok,
       %{
         "version" => 1,
         "kind" => "fount.writer_usefulness_evidence",
         "evidence_status" => Keyword.get(opts, :evidence_status, "recorded"),
         "human_study" => Keyword.get(opts, :human_study, "not_run"),
         "records" => records,
         "conditions_present" =>
           records |> Enum.map(& &1["condition"]) |> Enum.uniq() |> Enum.sort(),
         "dimensions_kept_separate" => @dimensions,
         "claims" => %{
           "aggregate_screenplay_score" => false,
           "automatic_winner" => false,
           "expert_endorsement" => false,
           "representative_sample" => false,
           "acceptance_rate_equals_quality" => false
         }
       }}
    end
  end

  def report(_, _), do: {:error, :invalid_usefulness_records}

  defp engineering(value) when is_map(value) do
    elapsed = value["elapsed_ms"]
    errors = list(value["errors"])
    completed = Map.get(value, "completed")

    cond do
      not is_nil(elapsed) and (not is_integer(elapsed) or elapsed < 0) ->
        {:error, :invalid_elapsed_ms}

      not is_boolean(completed) ->
        {:error, :engineering_completed_required}

      true ->
        {:ok,
         %{
           "completed" => completed,
           "elapsed_ms" => elapsed,
           "errors" => errors,
           "retries" => nonnegative(value["retries"], 0),
           "resource_usage" => value["resource_usage"] || %{}
         }}
    end
  end

  defp engineering(_), do: {:error, :invalid_engineering_evidence}

  defp human_response(attrs, outcome, kept_original) do
    dimensions = attrs["dimensions"] || %{}

    if is_map(dimensions) do
      {:ok,
       %{
         "outcome" => outcome,
         "kept_original" => kept_original,
         "preference" => attrs["preference"],
         "friction" => list(attrs["friction"]),
         "notes" => list(attrs["notes"]),
         "dimensions" => Map.take(dimensions, @dimensions)
       }}
    else
      {:error, :invalid_human_response_dimensions}
    end
  end

  defp validate_records(records) do
    if Enum.all?(records, &valid_record?/1), do: :ok, else: {:error, :invalid_usefulness_record}
  end

  defp valid_record?(
         %{
           "version" => 1,
           "task_id" => task_id,
           "condition" => condition,
           "output_refs" => output_refs,
           "engineering" => engineering,
           "human_response" => response
         } = record
       ) do
    Map.keys(record) |> Enum.sort() ==
      Enum.sort(~w(version task_id condition output_refs engineering human_response)) and
      is_binary(task_id) and condition in @conditions and is_list(output_refs) and
      valid_engineering?(engineering) and valid_human_response?(response)
  end

  defp valid_record?(_), do: false

  defp valid_engineering?(value) when is_map(value) do
    Map.keys(value) |> Enum.sort() ==
      Enum.sort(~w(completed elapsed_ms errors retries resource_usage)) and
      is_boolean(value["completed"]) and is_list(value["errors"]) and
      is_integer(value["retries"]) and value["retries"] >= 0
  end

  defp valid_engineering?(_), do: false

  defp valid_human_response?(value) when is_map(value) do
    Map.keys(value) |> Enum.sort() ==
      Enum.sort(~w(outcome kept_original preference friction notes dimensions)) and
      value["outcome"] in @outcomes and is_boolean(value["kept_original"]) and
      is_list(value["friction"]) and is_list(value["notes"]) and is_map(value["dimensions"])
  end

  defp valid_human_response?(_), do: false

  defp required_string(attrs, key) do
    value = attrs[key]

    if is_binary(value) and String.trim(value) != "",
      do: {:ok, value},
      else: {:error, {String.to_atom(key), :required}}
  end

  defp required_boolean(attrs, key) do
    case attrs[key] do
      value when is_boolean(value) -> {:ok, value}
      _ -> {:error, {String.to_atom(key), :required}}
    end
  end

  defp member(attrs, key, allowed) do
    value = attrs[key]
    if value in allowed, do: {:ok, value}, else: {:error, {String.to_atom(key), :invalid}}
  end

  defp list(nil), do: []
  defp list(value) when is_list(value), do: value
  defp list(value), do: [value]

  defp nonnegative(value, _default) when is_integer(value) and value >= 0, do: value
  defp nonnegative(_, default), do: default
end
