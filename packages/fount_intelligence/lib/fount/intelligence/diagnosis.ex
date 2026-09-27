defmodule Fount.Intelligence.Diagnosis do
  @moduledoc """
  Pure evidence-composed diagnosis.

  The module never acquires observations. An unassessed hypothesis becomes an
  explicit `EvidenceNeed`; uncertain or conflicting assessments remain visible
  instead of being converted into a screenplay-quality verdict.
  """

  alias Fount.Intelligence.Diagnosis.{Concern, EvidenceNeed, Result}
  alias Fount.Writing.CanonicalJSON

  @measurement "diagnosis.evidence_support"

  @doc "Purely reduces the first Observe pass into explicit context signals; it never filters source evidence."
  def reduce_base(assessments, evidence_ids) when is_list(assessments) and is_list(evidence_ids) do
    allowed = MapSet.new(evidence_ids)

    valid =
      Enum.all?(assessments, fn assessment ->
        is_map(assessment) and is_binary(assessment["evidence_id"]) and
          MapSet.member?(allowed, assessment["evidence_id"]) and
          is_binary(assessment["status"]) and
          (is_nil(assessment["relevance"]) or is_map(assessment["relevance"])) and
          is_list(assessment["observation_ids"] || [])
      end)

    if valid do
      signals = Enum.sort_by(assessments, & &1["evidence_id"])

      counts =
        Enum.reduce(signals, %{"supported" => 0, "uncertain" => 0, "not_supported" => 0, "error" => 0}, fn signal, acc ->
          status = get_in(signal, ["relevance", "status"]) || signal["status"] || "error"
          bucket = if Map.has_key?(acc, status), do: status, else: "error"
          Map.update!(acc, bucket, &(&1 + 1))
        end)

      {:ok, %{"signals" => signals, "counts" => counts, "evidence_filtered" => false}}
    else
      {:error, :invalid_base_assessments}
    end
  end

  def reduce_base(_, _), do: {:error, :invalid_base_assessments}

  @spec evaluate(Concern.t() | String.t() | map(), [map()], [map()] | map(), keyword()) ::
          {:ok, Result.t()} | {:error, atom()}
  def evaluate(concern, hypotheses, evidence, opts \\ []) do
    with {:ok, concern} <- normalize_concern(concern),
         {:ok, hypotheses} <- normalize_hypotheses(hypotheses),
         {:ok, evidence} <- normalize_evidence(evidence),
         true <- Keyword.keyword?(opts) do
      {diagnoses, needs, abstentions} =
        Enum.reduce(hypotheses, {[], [], []}, fn hypothesis, acc ->
          evaluate_hypothesis(concern, hypothesis, evidence, opts, acc)
        end)

      strengths =
        Enum.uniq(
          concern.protected_strengths ++
            Enum.flat_map(hypotheses, &Map.get(&1, "protected_strengths", []))
        )

      investigations =
        needs
        |> Enum.map(&investigation/1)
        |> Kernel.++(Enum.flat_map(abstentions, &Map.get(&1, "next_investigations", [])))
        |> Enum.uniq()

      {:ok,
       %Result{
         concern: concern,
         diagnoses: diagnoses,
         missing_evidence: needs,
         abstentions: abstentions,
         protected_strengths: strengths,
         next_investigations: investigations,
         evidence: Map.values(evidence) |> Enum.sort_by(& &1["id"]),
         limitations: [
           "Model-estimated support is evidence about a hypothesis, not a screenplay-quality score.",
           "No human reader agreement or usefulness calibration is implied."
         ]
       }}
    else
      false -> {:error, :invalid_diagnosis_request}
      {:error, _} = error -> error
      _ -> {:error, :invalid_diagnosis_request}
    end
  rescue
    _ -> {:error, :invalid_diagnosis_request}
  end

  defp evaluate_hypothesis(concern, hypothesis, evidence, _opts, {diagnoses, needs, abstentions}) do
    referenced = Map.get(hypothesis, "evidence_ids", [])
    unknown = Enum.reject(referenced, &Map.has_key?(evidence, &1))

    cond do
      unknown != [] ->
        need =
          evidence_need!(hypothesis, unknown, "Referenced source evidence is unavailable in the current request.")

        {diagnoses, needs ++ [need], abstentions ++ [abstention(hypothesis, "missing_source_evidence")]}

      is_nil(hypothesis["assessment"]) ->
        need =
          evidence_need!(
            hypothesis,
            referenced,
            "The hypothesis needs an explicit contextual support/counterevidence measurement."
          )

        {diagnoses, needs ++ [need], abstentions ++ [abstention(hypothesis, "needs_measurement")]}

      true ->
        case assessed_diagnosis(concern, hypothesis, evidence) do
          {:ok, diagnosis} -> {diagnoses ++ [diagnosis], needs, abstentions}
          {:abstain, record} -> {diagnoses, needs, abstentions ++ [record]}
        end
    end
  end

  defp assessed_diagnosis(concern, hypothesis, evidence) do
    assessment = hypothesis["assessment"]
    support = answer(assessment, "support")
    counter = answer(assessment, "counterevidence")
    support_status = support["status"]
    counter_status = counter["status"]

    support_ids = if support_status == "supported", do: hypothesis["evidence_ids"], else: []
    counter_ids = if counter_status == "supported", do: hypothesis["evidence_ids"], else: []

    cond do
      support_status == "supported" ->
        uncertainty =
          cond do
            counter_status == "supported" -> "high"
            counter_status in ["uncertain", "insufficient_evidence", "error"] -> "medium"
            true -> "low"
          end

        {:ok,
         %{
           "id" => diagnosis_id(concern.id, hypothesis),
           "code" => hypothesis["code"],
           "concern_id" => concern.id,
           "scope" => hypothesis["scope"],
           "hypothesis" => hypothesis["hypothesis"],
           "claim_class" => "model_estimated_interpretation",
           "support" => evidence_records(evidence, support_ids),
           "counterevidence" => evidence_records(evidence, counter_ids),
           "uncertainty" => uncertainty,
           "assessment" => assessment,
           "alternatives" => hypothesis["alternatives"],
           "missing_evidence" => [],
           "protected_strengths" => hypothesis["protected_strengths"],
           "next_investigations" => hypothesis["next_investigations"],
           "strategy_classes" => hypothesis["strategy_classes"],
           "provenance" => %{
             "measurement" => @measurement,
             "observation_ids" => Map.get(assessment, "observation_ids", [])
           }
         }}

      support_status in ["uncertain", "insufficient_evidence"] ->
        {:abstain,
         assessed_abstention(
           hypothesis,
           assessment,
           evidence,
           support_ids,
           counter_ids,
           "uncertain_support",
           ["Acquire more discriminating evidence or compare an alternative hypothesis."]
         )}

      support_status == "not_supported" and counter_status == "supported" ->
        {:abstain,
         assessed_abstention(
           hypothesis,
           assessment,
           evidence,
           support_ids,
           counter_ids,
           "counterevidence_dominates",
           ["Preserve the counterevidence and test another explanation for the writer concern."]
         )}

      true ->
        {:abstain,
         assessed_abstention(
           hypothesis,
           assessment,
           evidence,
           support_ids,
           counter_ids,
           "unsupported_or_unavailable",
           ["Investigate another hypothesis rather than treating this one as established."]
         )}
    end
  end

  defp evidence_need!(hypothesis, ids, reason) do
    {:ok, need} =
      EvidenceNeed.new(%{
        "measurement" => @measurement,
        "hypothesis_id" => hypothesis["id"],
        "reason" => reason,
        "evidence_ids" => ids,
        "context_requirements" => ["concern"],
        "optional" => false
      })

    need
  end

  defp investigation(%EvidenceNeed{} = need) do
    %{
      "id" => "investigate-" <> need.id,
      "kind" => "acquire_evidence",
      "measurement" => need.measurement,
      "hypothesis_id" => need.hypothesis_id,
      "evidence_ids" => need.evidence_ids,
      "reason" => need.reason
    }
  end

  defp abstention(hypothesis, reason, investigations \\ []) do
    %{
      "hypothesis_id" => hypothesis["id"],
      "code" => hypothesis["code"],
      "hypothesis" => hypothesis["hypothesis"],
      "reason" => reason,
      "alternatives" => hypothesis["alternatives"],
      "protected_strengths" => hypothesis["protected_strengths"],
      "support" => [],
      "counterevidence" => [],
      "assessment" => nil,
      "next_investigations" => investigations ++ hypothesis["next_investigations"]
    }
  end

  defp assessed_abstention(
         hypothesis,
         assessment,
         evidence,
         support_ids,
         counter_ids,
         reason,
         investigations
       ) do
    hypothesis
    |> abstention(reason, investigations)
    |> Map.put("assessment", assessment)
    |> Map.put("support", evidence_records(evidence, support_ids))
    |> Map.put("counterevidence", evidence_records(evidence, counter_ids))
  end

  defp normalize_concern(%Concern{} = concern), do: {:ok, concern}
  defp normalize_concern(value), do: Concern.new(value)

  defp normalize_hypotheses(values) when is_list(values) and values != [] do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case normalize_hypothesis(value) do
        {:ok, normalized} -> {:cont, {:ok, acc ++ [normalized]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, normalized} ->
        ids = Enum.map(normalized, & &1["id"])
        if length(ids) == length(Enum.uniq(ids)), do: {:ok, normalized}, else: {:error, :duplicate_hypothesis}

      error ->
        error
    end
  end

  defp normalize_hypotheses(_), do: {:error, :invalid_hypotheses}

  defp normalize_hypothesis(value) when is_map(value) do
    value = stringify(value)
    hypothesis = value["hypothesis"]
    code = value["code"] || "writer_hypothesis"
    evidence_ids = value["evidence_ids"] || []
    alternatives = value["alternatives"] || []
    strengths = value["protected_strengths"] || []
    next = value["next_investigations"] || []
    strategies = value["strategy_classes"] || []
    scope = value["scope"] || %{}

    identity = %{
      "code" => code,
      "hypothesis" => hypothesis,
      "scope" => scope,
      "evidence_ids" => evidence_ids
    }

    id = value["id"] || "hypothesis-" <> String.slice(CanonicalJSON.hash(identity), 0, 24)

    valid =
      text?(id) and text?(code) and text?(hypothesis) and strings?(evidence_ids) and
        strings?(alternatives) and strings?(strengths) and strings?(next) and strings?(strategies) and
        is_map(scope) and (is_nil(value["assessment"]) or is_map(value["assessment"]))

    if valid do
      {:ok,
       %{
         "id" => id,
         "code" => code,
         "hypothesis" => hypothesis,
         "scope" => scope,
         "evidence_ids" => Enum.uniq(evidence_ids),
         "alternatives" => alternatives,
         "protected_strengths" => strengths,
         "next_investigations" => next,
         "strategy_classes" => strategies,
         "assessment" => value["assessment"]
       }}
    else
      {:error, :invalid_hypothesis}
    end
  rescue
    _ -> {:error, :invalid_hypothesis}
  end

  defp normalize_hypothesis(_), do: {:error, :invalid_hypothesis}

  defp normalize_evidence(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, %{}}, fn value, {:ok, acc} ->
      case evidence_record(value) do
        {:ok, %{"id" => id} = record} ->
          if Map.has_key?(acc, id), do: {:halt, {:error, :duplicate_evidence}}, else: {:cont, {:ok, Map.put(acc, id, record)}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp normalize_evidence(values) when is_map(values), do: values |> Map.values() |> normalize_evidence()
  defp normalize_evidence(_), do: {:error, :invalid_evidence}

  defp evidence_record(value) when is_map(value) do
    value = stringify(value)
    id = value["id"] || value["evidence_id"]

    if text?(id) do
      {:ok,
       %{
         "id" => id,
         "claim_class" => value["claim_class"] || "canonical_fact",
         "target" => value["target"],
         "excerpt" => value["excerpt"],
         "role" => value["role"],
         "source_revision" => value["revision_id"] || value["source_revision"],
         "provenance" => value["provenance"] || %{}
       }}
    else
      {:error, :invalid_evidence}
    end
  end

  defp evidence_record(_), do: {:error, :invalid_evidence}

  defp evidence_records(evidence, ids), do: Enum.map(ids, &Map.fetch!(evidence, &1))

  defp answer(assessment, key) do
    case Map.get(assessment, key) do
      value when is_map(value) -> value
      _ -> %{"status" => "error", "reason" => "missing_assessment"}
    end
  end

  defp diagnosis_id(concern_id, hypothesis) do
    "diagnosis-" <>
      String.slice(
        CanonicalJSON.hash(%{"concern_id" => concern_id, "hypothesis_id" => hypothesis["id"]}),
        0,
        24
      )
  end

  defp stringify(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end

  defp text?(value), do: is_binary(value) and value != "" and String.valid?(value)
  defp strings?(values), do: is_list(values) and Enum.all?(values, &text?/1)
end
