defmodule FountProbe.Access do
  @moduledoc "Proposes exact character-access fragments from a prefix, then evaluates each access relation."
  alias Fount.Writing.Schema
  alias Fount.Writing.UTF8Span
  alias FountProbe.Completion
  alias FountProbe.Jev
  alias FountProbe.Projection

  @schema %{
    "type" => "object",
    "required" => ["entries"],
    "additionalProperties" => false,
    "properties" => %{
      "entries" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ~w(character_id evidence_id excerpt channel reason),
          "properties" => %{
            "character_id" => %{"type" => "string"},
            "evidence_id" => %{"type" => "string"},
            "excerpt" => %{"type" => "string", "minLength" => 1},
            "channel" => %{"enum" => ~w(sees hears is_told inference)},
            "reason" => %{"type" => "string"}
          }
        }
      }
    }
  }

  def build(model, point, character_ids, clients, opts \\ []) do
    with {:ok, state, evidence} <- Projection.at(model, point, "page_reader"),
         true <- not is_nil(clients[:inference]) do
      names = Map.new(character_ids, fn id -> {id, model.cast[id].display_name} end)

      prompt =
        "Identify ONLY candidate access to exact excerpts by the named characters before this cutoff. " <>
          "A cue, appearance, or reference does not establish attendance or seeing every action. A lie heard is a claim, not a fact. " <>
          "Quote only the accessible substring of an evidence excerpt. No later context is available. Return uncertain proposals for evaluation.\n" <>
          Jason.encode!(%{"characters" => names, "state" => state, "evidence" => evidence})

      with {:ok, object, trace} <-
             Completion.complete(
               clients.inference,
               prompt,
               @schema,
               &validate(&1, evidence, character_ids),
               opts
             ) do
        evaluate_proposal(model, point, clients, opts, %{
          state: state,
          evidence: evidence,
          names: names,
          object: object,
          trace: trace
        })
      end
    else
      false -> {:error, :missing_inference_client}
      error -> error
    end
  end

  defp evaluate_proposal(model, point, clients, opts, %{
         state: state,
         evidence: evidence,
         names: names,
         object: object,
         trace: trace
       }) do
    entries =
      Enum.with_index(object["entries"], fn entry, index ->
        locate_entry(entry, index, evidence, model, point)
      end)

    inputs = Enum.map(entries, &evaluation_input(&1, names, state))

    question =
      SystemOneSDK.choice(
        "Does the supplied prefix support this character receiving this specific fragment through this channel? Presence alone is insufficient.",
        supported: "Explicitly supported access.",
        plausible: "Plausible but not established.",
        unsupported: "Unsupported or denied access."
      )

    evaluate_entries(clients, opts, entries, inputs, trace, question)
  end

  defp locate_entry(entry, index, evidence, model, point) do
    registry = Map.new(evidence, &{&1["evidence_id"], &1})
    source = registry[entry["evidence_id"]]
    {:ok, {first, last}} = UTF8Span.relocate(source["excerpt"], entry["excerpt"])
    offset = source["target"]["span"]["byte_start"]

    target =
      put_in(source["target"], ["span"], %{
        "byte_start" => offset + first,
        "byte_end" => offset + last
      })

    Map.merge(entry, %{
      "id" => "access_#{index}",
      "target" => target,
      "revision_id" => model.revision.id,
      "as_of" => point
    })
  end

  defp evaluation_input(entry, names, state) do
    %{
      "id" => entry["id"],
      "state" => %{
        "character" => names[entry["character_id"]],
        "proposed_access" => Map.take(entry, ~w(excerpt channel reason)),
        "prefix" => state
      }
    }
  end

  defp evaluate_entries(clients, opts, entries, inputs, trace, question) do
    with {:ok, result} <-
           Jev.evaluate(
             clients[:system_one],
             inputs,
             [access: question],
             Keyword.put_new(opts, :profile_id, "access")
           ) do
      by_id = Map.new(result["entries"], &{&1["input_id"], &1})
      thresholds = Jev.threshold_options(result["profile_asset"])
      support_threshold = Keyword.get(thresholds, :supported, 0.8)
      confidence_threshold = Keyword.get(thresholds, :minimum_confidence, 0.7)

      ledger =
        Enum.map(entries, &ledger_entry(&1, by_id, support_threshold, confidence_threshold))

      {:ok, ledger, %{"completion" => trace, "evaluation" => result}}
    end
  end

  defp ledger_entry(entry, by_id, support_threshold, confidence_threshold) do
    answer = get_in(by_id, [entry["id"], "answers", "access"]) || %{}
    p = get_in(answer, ["probabilities", "supported"])
    confidence = answer["confidence"]

    Map.merge(entry, %{
      "access" => access_status(answer, p, confidence, support_threshold, confidence_threshold),
      "support_probability" => p,
      "confidence" => confidence,
      "access_support_threshold" => support_threshold,
      "access_confidence_threshold" => confidence_threshold
    })
  end

  defp access_status(answer, p, confidence, support_threshold, confidence_threshold) do
    cond do
      is_number(p) and p >= support_threshold and is_number(confidence) and
          confidence >= confidence_threshold ->
        "text_supported"

      answer["choice"] == "plausible" ->
        "plausible"

      answer["choice"] == "unsupported" and answer["status"] == "supported" ->
        "denied"

      true ->
        "unknown"
    end
  end

  defp validate(object, evidence, ids) do
    registry = Map.new(evidence, &{&1["evidence_id"], &1})

    with :ok <- Schema.validate(@schema, object),
         true <-
           Enum.all?(object["entries"], fn entry ->
             source = registry[entry["evidence_id"]]

             (entry["character_id"] in ids and source) &&
               match?(
                 {:ok, _},
                 UTF8Span.relocate(source["excerpt"], entry["excerpt"])
               )
           end) do
      :ok
    else
      false -> {:error, :invalid_access_evidence}
      error -> error
    end
  end
end
