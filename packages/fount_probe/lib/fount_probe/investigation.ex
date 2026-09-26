defmodule FountProbe.Investigation do
  @moduledoc "Finite, screenplay-specific investigation plans and evidence-backed hypothesis revision. Does not execute model-supplied code."
  alias Fount.Screenplay.Model
  alias Fount.Writing.Schema
  alias FountProbe.Catalog
  alias FountProbe.Completion
  alias FountProbe.Projection
  alias FountProbe.Report

  def plan(model, concern, clients, opts \\ []) do
    with true <- (is_binary(concern) and String.trim(concern) != "") or {:error, :empty_concern},
         {:ok, units} <-
           Projection.select(model, Keyword.get(opts, :selection, %{"whole_screenplay" => true})) do
      plan_selected(model, concern, clients, opts, units)
    end
  end

  defp plan_selected(model, concern, clients, opts, units) do
    schema = %{
      "type" => "object",
      "properties" => %{
        "hypotheses" => %{
          "type" => "array",
          "minItems" => 1,
          "maxItems" => 6,
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => nonempty(),
              "claim" => nonempty(),
              "reason" => nonempty(),
              "request_ids" => strings()
            },
            "required" => ~w(id claim reason request_ids),
            "additionalProperties" => false
          }
        },
        "requests" => %{
          "type" => "array",
          "minItems" => 1,
          "maxItems" => 6,
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "tool" => %{"enum" => Catalog.names()},
              "params" => %{"type" => "object"}
            },
            "required" => ~w(id tool params),
            "additionalProperties" => false
          }
        }
      },
      "required" => ~w(hypotheses requests),
      "additionalProperties" => false
    }

    validate = fn object ->
      with :ok <- Schema.validate(schema, object),
           do: validate_plan(model, object)
    end

    prompt =
      "Investigate this writer's specific creative question, not whether every scene follows a formula. Form tentative competing hypotheses and choose only needed catalog tools. Requests are inspections, never edits. Exact IDs below are authoritative. For any tool requiring selection, copy the supplied selection object exactly into params.selection; do not invent a selection shape.\n" <>
        Jason.encode!(%{
          "concern" => concern,
          "selection" => Keyword.get(opts, :selection, %{"whole_screenplay" => true}),
          "material" => units,
          "tools" => Catalog.tools(),
          "cast" => Model.plain(Map.values(model.cast))
        })

    # Catalog request params are tool-specific open objects. The provider's strict
    # structured-output schema cannot express them; keep the full local validator.
    with {:ok, value, traces} <-
           Completion.complete(
             clients[:inference],
             prompt,
             schema,
             validate,
             Keyword.put(opts, :force_json_text, true)
           ) do
      {:ok,
       Report.new(model, "investigation_plan", %{"concern" => concern}, %{
         data: value,
         evidence: Projection.evidence(units),
         provenance: %{"completions" => traces}
       })}
    end
  end

  def validate_plan(model, %{"hypotheses" => hypotheses, "requests" => requests})
      when is_list(hypotheses) and is_list(requests) do
    request_ids = Enum.map(requests, &if(is_map(&1), do: &1["id"], else: nil))
    hypothesis_ids = Enum.map(hypotheses, &if(is_map(&1), do: &1["id"], else: nil))

    cond do
      invalid_plan_size?(requests, hypotheses) ->
        {:error, :invalid_investigation_size}

      invalid_plan_ids?(request_ids, hypothesis_ids) ->
        {:error, :duplicate_or_invalid_investigation_id}

      not Enum.all?(hypotheses, &valid_plan_hypothesis?(&1, request_ids)) ->
        {:error, :invalid_hypothesis}

      true ->
        validate_requests(model, requests)
    end
  end

  def validate_plan(_, _), do: {:error, :invalid_investigation_plan}

  defp invalid_plan_size?(requests, hypotheses),
    do: requests == [] or length(requests) > 6 or hypotheses == [] or length(hypotheses) > 6

  defp invalid_plan_ids?(request_ids, hypothesis_ids),
    do: not unique_nonempty?(request_ids) or not unique_nonempty?(hypothesis_ids)

  defp valid_plan_hypothesis?(h, request_ids) do
    is_map(h) and is_binary(h["claim"]) and h["claim"] != "" and
      is_binary(h["reason"]) and h["reason"] != "" and
      is_list(h["request_ids"]) and h["request_ids"] != [] and
      Enum.all?(h["request_ids"], &(&1 in request_ids))
  end

  def explain(model, concern, reports, clients, opts \\ []) do
    evidence = reports |> Enum.flat_map(& &1.evidence) |> Enum.uniq_by(& &1["evidence_id"])
    ids = Enum.map(evidence, & &1["evidence_id"])

    schema = %{
      "type" => "object",
      "properties" => %{
        "answer" => %{"type" => "string"},
        "revised_hypotheses" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => nonempty(),
              "claim" => nonempty(),
              "reason" => nonempty(),
              "status" => %{"enum" => ~w(supported contradicted unresolved)},
              "evidence_ids" => strings()
            },
            "required" => ~w(id claim reason status evidence_ids),
            "additionalProperties" => false
          }
        },
        "uncertainties" => strings(),
        "evidence_ids" => strings(),
        "follow_up_requests" => %{
          "type" => "array",
          "maxItems" => 3,
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => nonempty(),
              "tool" => %{"enum" => Catalog.names()},
              "params" => %{"type" => "object"},
              "reason" => nonempty()
            },
            "required" => ~w(id tool params reason),
            "additionalProperties" => false
          }
        },
        "strategies" => %{
          "type" => "array",
          "minItems" => 3,
          "maxItems" => 3,
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "title" => %{"type" => "string"},
              "dramatic_mechanism" => %{"type" => "string"},
              "beats" => strings(),
              "evidence_ids" => strings()
            },
            "required" => ~w(id title dramatic_mechanism beats evidence_ids),
            "additionalProperties" => false
          }
        }
      },
      "required" => ~w(answer revised_hypotheses uncertainties evidence_ids strategies),
      "additionalProperties" => false
    }

    remaining = Keyword.get(opts, :followups_remaining, 0)

    validate = fn object ->
      with :ok <- Schema.validate(schema, object),
           do:
             validate_explanation(
               model,
               object,
               ids,
               remaining,
               Enum.map(Keyword.get(opts, :hypotheses, []), & &1["id"])
             )
    end

    payload = %{
      "concern" => concern,
      "initial_hypotheses" => Keyword.get(opts, :hypotheses, []),
      "reports" => Enum.map(reports, &Report.to_map/1),
      "followups_remaining" => remaining
    }

    prompt =
      "Answer the creative question using the actual reports. Return revised hypotheses as records with id, claim, reason, supported/contradicted/unresolved status, and evidence IDs. Missing results are unknown. Cite exact registry IDs; distinguish model interpretation from established text. Offer exactly three genuinely contrasting writing remedies with causal beats, no ranking or universal quality score. You may request one follow-up batch only when the provided remaining count permits it; otherwise return an empty follow_up_requests list. Do not claim any pages have been rewritten yet.\n" <>
        Jason.encode!(payload)

    with {:ok, value, traces} <-
           Completion.complete(
             clients[:inference],
             prompt,
             schema,
             validate,
             Keyword.put(opts, :force_json_text, true)
           ) do
      {:ok,
       Report.new(model, "investigation_explanation", %{"concern" => concern}, %{
         status:
           if(Enum.all?(reports, &(&1.status == "complete")), do: "complete", else: "partial"),
         data: Map.put_new(value, "follow_up_requests", []),
         evidence: evidence,
         provenance: %{"completions" => traces},
         source_revision_ids: reports |> Enum.flat_map(& &1.source_revision_ids) |> Enum.uniq()
       })}
    end
  end

  def validate_explanation(model, object, ids, remaining, initial_ids \\ [])

  def validate_explanation(model, object, ids, remaining, initial_ids) when is_map(object) do
    strategies = object["strategies"]
    hypotheses = object["revised_hypotheses"]
    followups = Map.get(object, "follow_up_requests", [])

    cond do
      invalid_strategy_ids?(strategies) ->
        {:error, :invalid_strategy_ids}

      invalid_hypothesis_ids?(hypotheses) ->
        {:error, :invalid_hypothesis_ids}

      unrevised_hypotheses?(hypotheses, initial_ids) ->
        {:error, :unrevised_hypotheses}

      not Enum.all?(hypotheses, &valid_revised_hypothesis?/1) ->
        {:error, :invalid_hypothesis}

      invalid_followups?(followups, remaining) ->
        {:error, :followup_limit_exceeded}

      duplicate_followups?(followups) ->
        {:error, :duplicate_followup_id}

      uninspected_evidence?(object, strategies, hypotheses, ids) ->
        {:error, :uninspected_evidence}

      true ->
        validate_requests(model, followups)
    end
  end

  def validate_explanation(_, _, _, _, _), do: {:error, :invalid_investigation_explanation}

  defp invalid_strategy_ids?(strategies),
    do:
      not is_list(strategies) or length(strategies) != 3 or
        not unique_nonempty?(Enum.map(strategies, &if(is_map(&1), do: &1["id"], else: nil)))

  defp invalid_hypothesis_ids?(hypotheses),
    do:
      not is_list(hypotheses) or hypotheses == [] or
        not unique_nonempty?(Enum.map(hypotheses, &if(is_map(&1), do: &1["id"], else: nil)))

  defp unrevised_hypotheses?(hypotheses, initial_ids),
    do:
      initial_ids != [] and
        MapSet.new(Enum.map(hypotheses, & &1["id"])) != MapSet.new(initial_ids)

  defp valid_revised_hypothesis?(h),
    do:
      is_map(h) and is_binary(h["claim"]) and String.trim(h["claim"]) != "" and
        is_binary(h["reason"]) and String.trim(h["reason"]) != "" and
        h["status"] in ~w(supported contradicted unresolved) and is_list(h["evidence_ids"])

  defp uninspected_evidence?(object, strategies, hypotheses, ids) do
    not Enum.all?(
      List.wrap(object["evidence_ids"]) ++
        Enum.flat_map(strategies ++ hypotheses, &List.wrap(&1["evidence_ids"])),
      &(&1 in ids)
    )
  end

  defp invalid_followups?(followups, remaining),
    do: not is_list(followups) or length(followups) > min(max(remaining, 0), 3)

  defp duplicate_followups?(followups),
    do: not unique_nonempty?(Enum.map(followups, &if(is_map(&1), do: &1["id"], else: nil)))

  defp validate_requests(model, requests) do
    Enum.reduce_while(requests, :ok, fn request, :ok ->
      case validate_request(model, request) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_request(model, request) do
    if is_map(request) and is_binary(request["id"]) and is_binary(request["tool"]) and
         is_map(request["params"]),
       do: Catalog.validate(model, request["tool"], request["params"]),
       else: {:error, :invalid_investigation_request}
  end

  defp unique_nonempty?(ids),
    do:
      Enum.all?(ids, &(is_binary(&1) and String.trim(&1) != "")) and
        length(ids) == length(Enum.uniq(ids))

  defp nonempty, do: %{"type" => "string", "minLength" => 1}

  defp strings, do: %{"type" => "array", "items" => %{"type" => "string"}}
end
