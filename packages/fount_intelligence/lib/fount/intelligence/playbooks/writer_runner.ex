defmodule Fount.Intelligence.Playbooks.WriterRunner do
  @moduledoc "Imperative Phase-5 multi-pass shell. Observe acquisition stays here; Diagnosis stays pure."

  alias Fount.Intelligence.Acquisition.{ContextBuilder, DiagnosticMeasurements, Measurements, Planner}
  alias Fount.Intelligence.Diagnosis
  alias Fount.Intelligence.Diagnosis.{EvidenceNeed, Result}
  alias Fount.Intelligence.Playbooks.WriterRegistry
  alias Fount.Intelligence.Reporting.WriterPacket
  alias Fount.Intelligence.Runner.Resources
  alias Fount.Observe.Budget

  @default_provider_cap 250

  @spec preflight(Fount.Screenplay.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def preflight(model, playbook, request, opts \\ []) do
    with {:ok, definition} <- WriterRegistry.fetch(playbook),
         {:ok, plan} <- Planner.plan(model, request, opts),
         {:ok, initial} <- Diagnosis.evaluate(plan["concern"], plan["hypotheses"], plan["evidence"]),
         needed_ids = MapSet.new(Enum.map(initial.missing_evidence, & &1.hypothesis_id)),
         pending = Enum.filter(plan["hypotheses"], &MapSet.member?(needed_ids, &1["id"])),
         {:ok, cap} <- provider_cap(opts),
         {:ok, contextual_inputs} <- contextual_inputs(plan, pending, []),
         {:ok, base} <- measurement_preflight(plan["base_inputs"], DiagnosticMeasurements.base(), model, opts, min(cap, length(plan["base_inputs"]))),
         remaining = max(cap - min(cap, length(plan["base_inputs"])), 0),
         {:ok, contextual} <- measurement_preflight(contextual_inputs, DiagnosticMeasurements.support(), model, opts, remaining) do
      estimate = %{
        "targets" => length(plan["base_inputs"]) + length(contextual_inputs),
        "base_targets" => length(plan["base_inputs"]),
        "contextual_targets" => length(contextual_inputs),
        "provider_requests_before_retries_estimate" =>
          min(cap, length(plan["base_inputs"]) + length(contextual_inputs)),
        "hosted_cost" => nil,
        "reuse_estimate" => nil
      }

      {:ok,
       %{
         "playbook" => definition,
         "source_revision" => plan["source_revision"],
         "evidence_scope" => plan["evidence_scope"],
         "estimate" => estimate,
         "caps" => %{
           "max_provider_requests" => cap,
           "max_measurement_states" => Keyword.get(opts, :max_measurement_states, 500),
           "max_evidence_fragments" => Keyword.get(opts, :max_evidence_fragments, 48)
         },
         "passes" => %{"base" => base, "contextual" => contextual},
         "limitations" => [
           "Preflight performs no provider dispatch and reserves no analysis budget.",
           "Hosted cost and cache reuse remain unknown until a provider/runtime reports them.",
           "Contextual byte estimates omit model answers from the preceding base pass; execution records actual scheduled work."
         ]
       }}
    end
  end

  @spec run(Fount.Screenplay.t(), String.t(), map(), map(), keyword()) ::
          {:ok, WriterPacket.t()} | {:error, term()}
  def run(model, playbook, request, clients \\ %{}, opts \\ []) do
    with {:ok, definition} <- WriterRegistry.fetch(playbook),
         {:ok, provider} <- provider(clients),
         {:ok, preflight} <- preflight(model, playbook, request, opts),
         {:ok, plan} <- Planner.plan(model, request, opts),
         {:ok, cap} <- provider_cap(opts) do
      budget = Resources.from_options(opts) || Resources.new(opts)
      opts = Keyword.put(opts, :analysis_budget, budget)

      base_spec = DiagnosticMeasurements.base()
      base_cap = min(cap, length(plan["base_inputs"]))

      with {:ok, base} <-
             Measurements.evaluate(
               provider,
               plan["base_inputs"],
               base_spec["questions"],
               measurement_opts(opts, model, base_spec["lens_id"], base_cap)
             ),
           base_assessments = base_assessments(plan, base),
           {:ok, base_reduction} <-
             Diagnosis.reduce_base(base_assessments, Enum.map(plan["evidence"], & &1["evidence_id"])),
           {:ok, first_pass} <- Diagnosis.evaluate(plan["concern"], plan["hypotheses"], plan["evidence"]),
           needed_ids = MapSet.new(Enum.map(first_pass.missing_evidence, & &1.hypothesis_id)),
           pending = Enum.filter(plan["hypotheses"], &MapSet.member?(needed_ids, &1["id"])),
           {:ok, contextual_inputs} <- contextual_inputs(plan, pending, base_reduction["signals"]),
           remaining = max(cap - base["scheduled"], 0),
           {:ok, contextual} <- contextual_run(provider, contextual_inputs, model, opts, remaining),
           assessed = merge_assessments(plan["hypotheses"], contextual),
           {:ok, final} <- Diagnosis.evaluate(plan["concern"], assessed, plan["evidence"]),
           {:ok, packet} <- packet(definition, plan, preflight, base, contextual, base_reduction, first_pass, final, budget) do
        {:ok, packet}
      end
    end
  rescue
    _ in [ArgumentError, KeyError, FunctionClauseError, MatchError, BadMapError] ->
      {:error, :invalid_writer_playbook_request}
  end

  defp measurement_preflight(inputs, spec, model, opts, cap) do
    Measurements.preflight(inputs, spec["questions"], measurement_opts(opts, model, spec["lens_id"], cap))
  end

  defp contextual_run(_provider, [], _model, _opts, _cap), do: {:ok, empty_measurement_report()}

  defp contextual_run(provider, inputs, model, opts, cap) do
    spec = DiagnosticMeasurements.support()
    Measurements.evaluate(provider, inputs, spec["questions"], measurement_opts(opts, model, spec["lens_id"], cap))
  end

  defp contextual_inputs(plan, hypotheses, base_assessments) do
    source_by_id = Map.new(plan["evidence"], &{&1["evidence_id"], &1})

    Enum.reduce_while(hypotheses, {:ok, []}, fn hypothesis, {:ok, acc} ->
      evidence = Enum.map(hypothesis["evidence_ids"], &Map.get(source_by_id, &1))

      if evidence == [] or Enum.any?(evidence, &is_nil/1) do
        {:halt, {:error, :missing_source_evidence}}
      else
        assessments = Enum.filter(base_assessments, &(&1["evidence_id"] in hypothesis["evidence_ids"]))

        case ContextBuilder.build(
               DiagnosticMeasurements.support()["lens_id"],
               plan["concern"],
               hypothesis["context"] || %{},
               assessments
             ) do
          {:ok, context} ->
            input = %{
              "id" => "hypothesis:" <> hypothesis["id"],
              "state" => %{
                "concern" => Diagnosis.Concern.to_map(plan["concern"]),
                "hypothesis" => Map.take(hypothesis, ~w(id code hypothesis alternatives protected_strengths)),
                "evidence" =>
                  Enum.map(evidence, fn source ->
                    %{
                      "evidence_id" => source["evidence_id"],
                      "excerpt" => source["excerpt"],
                      "target" => source["target"]
                    }
                  end)
              },
              "target" => hd(evidence)["target"],
              "evidence" => evidence,
              "context" => context
            }

            {:cont, {:ok, acc ++ [input]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    end)
  end

  defp base_assessments(plan, report) do
    evidence_by_input =
      Map.new(plan["base_inputs"], fn input ->
        source = hd(input["evidence"])
        {input["id"], source["evidence_id"]}
      end)

    Enum.map(report["entries"], fn entry ->
      %{
        "evidence_id" => evidence_by_input[entry["input_id"]],
        "status" => entry["status"],
        "relevance" => get_in(entry, ["answers", "relevant"]),
        "observation_ids" => Enum.map(entry["observations"] || [], & &1["id"])
      }
    end)
  end

  defp merge_assessments(hypotheses, report) do
    entries = Map.new(report["entries"], &{&1["input_id"], &1})

    Enum.map(hypotheses, fn hypothesis ->
      case entries["hypothesis:" <> hypothesis["id"]] do
        %{"status" => "complete"} = entry ->
          assessment = %{
            "support" => get_in(entry, ["answers", "support"]),
            "counterevidence" => get_in(entry, ["answers", "counterevidence"]),
            "observation_ids" => Enum.map(entry["observations"] || [], & &1["id"])
          }

          Map.put(hypothesis, "assessment", assessment)

        _ ->
          hypothesis
      end
    end)
  end

  defp packet(definition, plan, preflight, base, contextual, base_reduction, first_pass, final, budget) do
    final_map = Result.to_map(final)
    errors = base["errors"] ++ contextual["errors"]
    skipped = skipped(base) ++ skipped(contextual)

    acquisition_complete = base["status"] == "complete" and contextual["status"] == "complete"
    evidence_complete = final.missing_evidence == []
    selection_complete = not plan["evidence_scope"]["truncated_by_host_limit"]
    status = if acquisition_complete and evidence_complete and selection_complete, do: "complete", else: "partial"

    coverage = %{
      "status" => status,
      "selected_evidence_fragments" => length(plan["evidence"]),
      "evidence_scope" => plan["evidence_scope"],
      "base_requested" => base["requested"],
      "base_received" => base["received"],
      "hypotheses_requested" => length(plan["hypotheses"]),
      "contextual_requested" => contextual["requested"],
      "contextual_received" => contextual["received"],
      "diagnoses_established" => length(final.diagnoses),
      "abstentions" => length(final.abstentions),
      "skipped_or_failed_request_ids" => skipped
    }

    resource_usage = %{
      "preflight" => preflight,
      "actual" => %{
        "base" => base["resource_usage"],
        "contextual" => contextual["resource_usage"],
        "analysis_budget" => Budget.snapshot(budget),
        "hosted_cost" => hosted_cost(base, contextual)
      }
    }

    counterevidence =
      (final.diagnoses ++ final.abstentions)
      |> Enum.flat_map(&Map.get(&1, "counterevidence", []))
      |> Enum.uniq_by(& &1["id"])

    alternatives =
      (final.diagnoses ++ final.abstentions)
      |> Enum.flat_map(&Map.get(&1, "alternatives", []))
      |> Enum.uniq()

    finding = concise_finding(final)

    uncertainty =
      Enum.map(final.diagnoses, fn diagnosis ->
        %{"diagnosis_id" => diagnosis["id"], "uncertainty" => diagnosis["uncertainty"]}
      end)

    analysis_passes = [
      %{"pass" => 0, "kind" => "observe_base", "status" => base["status"]},
      %{
        "pass" => 1,
        "kind" => "pure_evidence_need_reduction",
        "needs" => length(first_pass.missing_evidence)
      },
      %{"pass" => 2, "kind" => "contextual_observe", "status" => contextual["status"]},
      %{
        "pass" => 3,
        "kind" => "pure_diagnosis",
        "diagnoses" => length(final.diagnoses),
        "abstentions" => length(final.abstentions)
      }
    ]

    WriterPacket.new(definition["id"], plan["source_revision"], Diagnosis.Concern.to_map(plan["concern"]), %{
      status: status,
      scope: plan["concern"].scope,
      intent: writer_intent(plan),
      finding: finding,
      coverage: coverage,
      evidence: plan["evidence"],
      derived_state: %{
        "base_reduction" => base_reduction,
        "first_pass_missing_evidence" =>
          Enum.map(first_pass.missing_evidence, &EvidenceNeed.to_map/1)
      },
      trajectory: [],
      diagnoses: final.diagnoses,
      abstentions: final.abstentions,
      counterevidence: counterevidence,
      alternatives: alternatives,
      uncertainty: uncertainty,
      missing_evidence: final_map["missing_evidence"],
      protected_strengths: final.protected_strengths,
      next_investigations: final.next_investigations,
      strategies: plan["strategies"],
      revision_comparison: plan["revision_comparison"],
      resource_usage: resource_usage,
      errors: errors,
      provenance: %{
        "playbook_definition" => definition,
        "analysis_passes" => analysis_passes,
        "base_measurement_spec_sha256" => base["measurement_spec_sha256"],
        "contextual_measurement_spec_sha256" => contextual["measurement_spec_sha256"]
      },
      limitations: final.limitations ++ [
        "The ten Phase-5 playbooks provide a diagnosis shell; capability-family semantics remain later phases.",
        "No human usefulness or reader-agreement claim is made unless a separate rights-cleared study records one."
      ],
      candidate: nil
    })
  end

  defp concise_finding(%Result{} = result) do
    hypotheses = Enum.map(result.diagnoses, & &1["hypothesis"])

    case hypotheses do
      [] ->
        "No diagnostic hypothesis is established from the current evidence; inspect abstentions and missing evidence."

      [hypothesis] ->
        "The current evidence supports this hypothesis: #{hypothesis} Counterevidence and uncertainty remain explicit below."

      hypotheses ->
        shown = hypotheses |> Enum.take(3) |> Enum.join("; ")
        remainder = max(length(hypotheses) - 3, 0)
        suffix = if remainder > 0, do: " (+#{remainder} more)", else: ""

        "The current evidence supports multiple competing explanations: #{shown}#{suffix}. None is selected as the single explanation."
    end
  end

  defp writer_intent(plan) do
    concern = plan["concern"]

    %{
      "desired_effect" => concern.desired_effect,
      "constraints" => concern.intent,
      "playbook_intent" => plan["intent"]
    }
  end

  defp measurement_opts(opts, model, lens_id, cap) do
    opts
    |> Keyword.put(:source_model, model)
    |> Keyword.put(:lens_id, lens_id)
    |> Keyword.put(:max_provider_requests, max(cap, 0))
  end

  defp provider(clients) when is_map(clients) do
    case Map.get(clients, :observe, Map.get(clients, "observe")) do
      nil -> {:error, :observe_provider_required}
      provider -> {:ok, provider}
    end
  end

  defp provider(_), do: {:error, :observe_provider_required}

  defp provider_cap(opts) when is_list(opts) do
    value = Keyword.get(opts, :max_playbook_provider_requests, @default_provider_cap)
    if is_integer(value) and value >= 0 and value <= 10_000, do: {:ok, value}, else: {:error, :invalid_resource_cap}
  end

  defp provider_cap(_), do: {:error, :invalid_resource_cap}

  defp skipped(report) do
    for entry <- report["entries"], entry["status"] != "complete", do: entry["input_id"]
  end

  defp hosted_cost(base, contextual) do
    values = [get_in(base, ["resource_usage", "actual", "hosted_cost"]), get_in(contextual, ["resource_usage", "actual", "hosted_cost"])]
    if Enum.all?(values, &is_number/1), do: Enum.sum(values), else: nil
  end

  defp empty_measurement_report do
    %{
      "entries" => [],
      "status" => "complete",
      "errors" => [],
      "requested" => 0,
      "scheduled" => 0,
      "received" => 0,
      "cache_hits" => 0,
      "provider_batches" => 0,
      "elapsed_ms" => 0,
      "resource_usage" => %{
        "preflight" => %{},
        "actual" => %{
          "scheduled_states" => 0,
          "successful_states" => 0,
          "cache_hits" => 0,
          "provider_requests" => 0,
          "initial_provider_requests_scheduled" => 0,
          "reported_retries" => 0,
          "hosted_cost" => nil,
          "usage_reported" => []
        }
      },
      "measurement_spec_sha256" => nil,
      "measurement_spec" => %{},
      "lens_asset" => nil,
      "state_hashes" => %{}
    }
  end
end
