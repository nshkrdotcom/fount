defmodule FountRun.SemanticAssessmentHandler do
  @moduledoc "Durable, non-mutating SI02 semantic-import stages."
  @behaviour FountRun.StageHandler

  alias Fount.Persistence, as: CorePersistence
  alias FountRun.{DispatchHook, ExecutionStore, Persistence, PipelineRequest}
  alias FountWorkshop.SemanticAssessment
  alias FountWorkshop.Writing.Budget

  @stages ~w(semantic_intake semantic_plan semantic_extract semantic_reconcile semantic_validate semantic_persist)

  @impl true
  def execute(%{"stage" => stage} = claim, opts) when stage in @stages do
    result =
      with {:ok, envelope} <- PipelineRequest.validate(claim["request"]),
           "semantic_import_v2" <- envelope["kind"],
           :ok <- verify_checkpoint(claim, envelope, opts) do
        execute_stage(stage, claim, envelope, opts)
      else
        {:error, _} = error -> error
        _ -> {:error, :invalid_semantic_pipeline_request}
      end

    maybe_mark_failure(result, claim, opts)
  end

  def execute(%{"stage" => stage}, _opts), do: {:error, {:invalid_semantic_stage, stage}}
  def execute(_, _opts), do: {:error, :invalid_semantic_claim}

  defp execute_stage("semantic_intake", claim, envelope, opts) do
    request = envelope["semantic_request"]
    repo = Keyword.fetch!(opts, :repo)

    with :ok <- enforce_policy(request),
         {:ok, run} <-
           FountRun.get_run(repo, claim["run_id"], Keyword.fetch!(opts, :actor_context)),
         true <-
           request["screenplay_id"] == run["screenplay_id"] or
             {:error, :semantic_screenplay_binding_mismatch},
         true <-
           request["revision_id"] == run["plan"]["base_revision_id"] or
             {:error, :semantic_revision_binding_mismatch},
         {:ok, screenplay} <-
           CorePersistence.load_revision(
             repo,
             run["screenplay_id"],
             run["plan"]["base_revision_id"]
           ),
         {:ok, descriptor} <- SemanticAssessment.source_descriptor(screenplay),
         :ok <- source_binding(request, descriptor),
         :ok <-
           store_action(opts, :status, %{
             "assessment_id" => request["assessment_id"],
             "status" => "running"
           }),
         {:ok, next} <-
           schedule(
             repo,
             claim,
             "semantic_plan",
             Map.put(envelope, "semantic_runtime", %{"source" => descriptor}),
             opts
           ) do
      {:ok,
       %{
         "status" => "semantic_preflight_saved",
         "scheduled_step_id" => next["id"],
         "model" => request["model"],
         "reasoning_effort" => request["reasoning_effort"],
         "changes_canon" => false,
         "next_stage" => "semantic_plan"
       }}
    end
  end

  defp execute_stage("semantic_plan", claim, envelope, opts) do
    repo = Keyword.fetch!(opts, :repo)
    source = get_in(envelope, ["semantic_runtime", "source", "visible_source"])

    with true <- is_binary(source) or {:error, :semantic_source_missing},
         {:ok, plan} <-
           SemanticAssessment.plan_source(source,
             limits: envelope["semantic_request"]["limits"] || %{},
             scene_starts: get_in(envelope, ["semantic_runtime", "source", "scene_starts"]) || [],
             metadata_ranges:
               get_in(envelope, ["semantic_runtime", "source", "metadata_ranges"]) || []
           ),
         :ok <- validate_inference_ceiling(envelope["semantic_request"], plan),
         runtime <-
           Map.merge(envelope["semantic_runtime"] || %{}, %{
             "plan" => plan,
             "extract_index" => 0,
             "chunk_results" => [],
             "usage_trace" => []
           }),
         :ok <-
           store_action(opts, :progress, %{
             "assessment_id" => envelope["semantic_request"]["assessment_id"],
             "coverage" => progress_coverage(plan, 0)
           }),
         {:ok, next} <-
           schedule(
             repo,
             claim,
             "semantic_extract",
             Map.put(envelope, "semantic_runtime", runtime),
             opts,
             "0"
           ) do
      {:ok,
       %{
         "status" => "semantic_chunks_planned",
         "chunk_count" => plan["chunk_count"],
         "source_bytes" => plan["source_bytes"],
         "scheduled_step_id" => next["id"],
         "changes_canon" => false,
         "next_stage" => "semantic_extract"
       }}
    else
      {:error, _} = error -> error
    end
  end

  defp execute_stage("semantic_extract", claim, envelope, opts) do
    repo = Keyword.fetch!(opts, :repo)
    runtime = envelope["semantic_runtime"] || %{}
    plan = runtime["plan"] || %{}
    index = runtime["extract_index"] || 0
    chunks = plan["chunks"] || []

    case Enum.at(chunks, index) do
      nil ->
        schedule_reconcile(repo, claim, envelope, runtime, opts)

      chunk ->
        extract_chunk(repo, claim, envelope, runtime, {plan, index, chunks, chunk}, opts)
    end
  end

  defp execute_stage("semantic_reconcile", claim, envelope, opts) do
    repo = Keyword.fetch!(opts, :repo)
    runtime = envelope["semantic_runtime"] || %{}
    results = runtime["chunk_results"] || []

    with {:ok, client} <- inference(opts),
         {:ok, completion_opts} <- completion_opts(repo, claim, opts) do
      reconcile_result(
        normalize_reconciliation(
          SemanticAssessment.reconcile(
            client,
            results,
            Keyword.merge(completion_opts,
              plan: runtime["plan"],
              binding: prompt_binding(envelope["semantic_request"], runtime["source"])
            )
          )
        ),
        repo,
        claim,
        envelope,
        runtime,
        opts
      )
    end
  end

  defp execute_stage("semantic_validate", claim, envelope, opts) do
    repo = Keyword.fetch!(opts, :repo)
    runtime = envelope["semantic_runtime"] || %{}
    request = envelope["semantic_request"]
    binding = prompt_binding(request, runtime["source"] || %{})

    with {:ok, aggregate} <-
           SemanticAssessment.assemble(
             runtime["chunk_results"] || [],
             runtime["reconciliation"],
             binding,
             limits: request["limits"] || %{},
             plan: runtime["plan"],
             expected_chunk_count: get_in(runtime, ["plan", "chunk_count"]) || 0
           ),
         runtime <- Map.put(runtime, "aggregate", aggregate),
         {:ok, next} <-
           schedule(
             repo,
             claim,
             "semantic_persist",
             Map.put(envelope, "semantic_runtime", runtime),
             opts
           ) do
      {:ok,
       %{
         "status" => "semantic_result_validated",
         "entities" => length(aggregate["entities"]),
         "occurrences" => length(aggregate["occurrences"]),
         "scheduled_step_id" => next["id"],
         "changes_canon" => false,
         "next_stage" => "semantic_persist"
       }}
    end
  end

  defp execute_stage("semantic_persist", claim, envelope, opts) do
    request = envelope["semantic_request"]
    runtime = envelope["semantic_runtime"] || %{}
    aggregate = runtime["aggregate"]

    status =
      if is_binary(runtime["partial_reason"]) or
           get_in(aggregate, ["coverage", "complete"]) != true or
           aggregate["unresolved"] != [],
         do: "partial",
         else: "ready"

    payload = %{
      "assessment_id" => request["assessment_id"],
      "run_id" => claim["run_id"],
      "status" => status,
      "result" => aggregate,
      "coverage" => aggregate["coverage"],
      "usage_trace" => runtime["usage_trace"] || [],
      "provider_returned_model" => returned_model(runtime["usage_trace"] || []),
      "partial_reason" => runtime["partial_reason"]
    }

    with :ok <- store_action(opts, :result, payload) do
      {:ok,
       %{
         "status" => "semantic_assessment_persisted",
         "assessment_id" => request["assessment_id"],
         "assessment_status" => status,
         "run_status" => "completed_nonmutating",
         "changes_canon" => false
       }}
    end
  end

  defp verify_checkpoint(claim, envelope, opts) do
    repo = Keyword.fetch!(opts, :repo)
    request = envelope["semantic_request"]
    context = Keyword.fetch!(opts, :actor_context)

    with :ok <- enforce_policy(request),
         {:ok, run} <- FountRun.get_run(repo, claim["run_id"], context),
         true <-
           request["revision_id"] == run["plan"]["base_revision_id"] or
             {:error, :semantic_revision_binding_mismatch},
         true <-
           request["screenplay_id"] == run["screenplay_id"] or
             {:error, :semantic_screenplay_binding_mismatch},
         {:ok, screenplay} <-
           CorePersistence.load_revision(repo, run["screenplay_id"], request["revision_id"]),
         {:ok, source} <- SemanticAssessment.source_descriptor(screenplay),
         :ok <- source_binding(request, source) do
      verify_runtime_source(envelope["semantic_runtime"], request, source)
    end
  end

  defp verify_runtime_source(nil, _request, _source), do: :ok

  defp verify_runtime_source(runtime, request, source) do
    with true <- runtime["source"] == source or {:error, :semantic_checkpoint_source_mismatch},
         {:ok, plan} <-
           SemanticAssessment.plan_source(source["visible_source"],
             limits: request["limits"],
             scene_starts: source["scene_starts"],
             metadata_ranges: source["metadata_ranges"]
           ),
         true <- runtime["plan"] in [nil, plan] or {:error, :semantic_checkpoint_plan_mismatch},
         :ok <- SemanticAssessment.validate_checkpoint(runtime, prompt_binding(request, source)) do
      verify_checkpoint_aggregate(runtime, request, source)
    end
  end

  defp verify_checkpoint_aggregate(%{"aggregate" => aggregate} = runtime, request, source) do
    with {:ok, expected} <-
           SemanticAssessment.assemble(
             runtime["chunk_results"],
             runtime["reconciliation"],
             prompt_binding(request, source),
             limits: request["limits"],
             plan: runtime["plan"],
             expected_chunk_count: runtime["plan"]["chunk_count"]
           ),
         true <- aggregate == expected or {:error, :semantic_checkpoint_aggregate_mismatch} do
      :ok
    end
  end

  defp verify_checkpoint_aggregate(_runtime, _request, _source), do: :ok

  defp extraction_next_stage(index, chunks) do
    if index + 1 < length(chunks), do: "semantic_extract", else: "semantic_reconcile"
  end

  defp extract_chunk(repo, claim, envelope, runtime, {plan, index, chunks, chunk}, opts) do
    with {:ok, client} <- inference(opts),
         {:ok, completion_opts} <- completion_opts(repo, claim, opts),
         binding <- prompt_binding(envelope["semantic_request"], runtime["source"] || %{}),
         result <- SemanticAssessment.extract(client, chunk, binding, completion_opts),
         {:ok, object, trace} <- normalize_completion(result),
         :ok <- validate_returned_models(trace),
         runtime <-
           runtime
           |> Map.put("extract_index", index + 1)
           |> Map.update("chunk_results", [object], &(&1 ++ [object]))
           |> Map.update("usage_trace", trace, &(&1 ++ trace)),
         :ok <-
           store_action(opts, :progress, %{
             "assessment_id" => envelope["semantic_request"]["assessment_id"],
             "coverage" => progress_coverage(plan, index + 1)
           }),
         next_stage <- extraction_next_stage(index, chunks),
         {:ok, next} <-
           schedule(
             repo,
             claim,
             next_stage,
             Map.put(envelope, "semantic_runtime", runtime),
             opts,
             Integer.to_string(index + 1)
           ) do
      {:ok,
       %{
         "status" => "semantic_chunk_extracted",
         "chunk_id" => chunk["chunk_id"],
         "completed_chunks" => index + 1,
         "chunk_count" => length(chunks),
         "scheduled_step_id" => next["id"],
         "changes_canon" => false,
         "next_stage" => next_stage
       }}
    end
  end

  defp reconcile_result({:ok, reconciliation, trace}, repo, claim, envelope, runtime, opts) do
    with :ok <- validate_returned_models(trace) do
      runtime =
        runtime
        |> Map.put("reconciliation", reconciliation)
        |> Map.update("usage_trace", trace, &(&1 ++ trace))

      with {:ok, next} <-
             schedule(
               repo,
               claim,
               "semantic_validate",
               Map.put(envelope, "semantic_runtime", runtime),
               opts
             ) do
        {:ok,
         %{
           "status" => "semantic_reconciled",
           "scheduled_step_id" => next["id"],
           "changes_canon" => false,
           "next_stage" => "semantic_validate"
         }}
      end
    end
  end

  defp reconcile_result({:partial, reason, bytes}, repo, claim, envelope, runtime, opts) do
    runtime =
      runtime
      |> Map.put("reconciliation", %{
        "groups" => [],
        "unresolved" => [
          %{
            "members" => [],
            "reason" => "unsupported_scope",
            "explanation" =>
              "Cross-chunk reconciliation was omitted because the validated entity index exceeded the configured context limit (#{bytes} bytes)."
          }
        ]
      })
      |> Map.put("partial_reason", to_string(reason))

    with {:ok, next} <-
           schedule(
             repo,
             claim,
             "semantic_validate",
             Map.put(envelope, "semantic_runtime", runtime),
             opts
           ) do
      {:ok,
       %{
         "status" => "semantic_reconciliation_partial",
         "scheduled_step_id" => next["id"],
         "changes_canon" => false,
         "next_stage" => "semantic_validate"
       }}
    end
  end

  defp reconcile_result({:error, _} = error, _repo, _claim, _envelope, _runtime, _opts), do: error

  defp schedule_reconcile(repo, claim, envelope, runtime, opts) do
    with {:ok, next} <-
           schedule(
             repo,
             claim,
             "semantic_reconcile",
             Map.put(envelope, "semantic_runtime", runtime),
             opts
           ) do
      {:ok,
       %{
         "status" => "semantic_extraction_complete",
         "scheduled_step_id" => next["id"],
         "changes_canon" => false,
         "next_stage" => "semantic_reconcile"
       }}
    end
  end

  defp schedule(repo, claim, stage, request, opts, suffix \\ nil) do
    context = Keyword.fetch!(opts, :actor_context)
    suffix = suffix || stage

    Persistence.create_step(
      repo,
      claim["run_id"],
      %{
        "stage" => stage,
        "iteration" => claim["iteration"],
        "branch_id" => claim["branch_id"] || "semantic",
        "input_revision_id" => claim["input_revision_id"],
        "input_candidate_id" => nil,
        "idempotency_key" =>
          claim["operation_key"] <> ":semantic-next:" <> stage <> ":" <> suffix,
        "request" => request
      },
      context
    )
  end

  defp completion_opts(repo, claim, opts) do
    with {:ok, limits} <- ExecutionStore.remaining_limits(repo, claim) do
      budget = Budget.new(max_inference_calls: limits.max_inference_calls)

      {:ok,
       [
         budget: budget,
         decode_repairs: min(limits.decode_repairs, 1),
         transient_retries: limits.transient_retries,
         dispatch_hook: DispatchHook.new(repo, claim, Keyword.put(opts, :audit_validation, true)),
         reserved_cost_microunits: Keyword.get(opts, :reserved_cost_microunits),
         currency: Keyword.get(opts, :currency)
       ]}
    end
  end

  defp normalize_reconciliation({:error, reason, _trace}), do: {:error, reason}
  defp normalize_reconciliation(result), do: result

  defp normalize_completion({:ok, object, trace}) when is_map(object) and is_list(trace),
    do: {:ok, object, trace}

  defp normalize_completion({:error, reason, _trace}), do: {:error, reason}
  defp normalize_completion(_), do: {:error, :invalid_semantic_completion}

  defp inference(opts) do
    case Keyword.fetch(opts, :inference) do
      {:ok, client} -> {:ok, client}
      :error -> {:error, :semantic_inference_unavailable}
    end
  end

  defp store_action(opts, action, payload) do
    case Keyword.get(opts, :semantic_store) do
      fun when is_function(fun, 2) ->
        case fun.(action, payload) do
          :ok -> :ok
          {:ok, _} -> :ok
          {:error, _} = error -> error
          _ -> {:error, :semantic_store_invalid_response}
        end

      _ ->
        {:error, :semantic_store_unavailable}
    end
  end

  defp maybe_mark_failure({:error, reason} = error, claim, opts) do
    request = get_in(claim, ["request", "semantic_request"]) || %{}

    _ =
      store_action(opts, :status, %{
        "assessment_id" => request["assessment_id"],
        "status" => "failed",
        "error" => safe_reason(reason)
      })

    error
  end

  defp maybe_mark_failure(result, _claim, _opts), do: result

  defp enforce_policy(request) do
    cond do
      request["schema_version"] != SemanticAssessment.schema_version() ->
        {:error, :semantic_schema_version_mismatch}

      request["prompt_version"] != SemanticAssessment.prompt_version() ->
        {:error, :semantic_prompt_version_mismatch}

      request["model"] != SemanticAssessment.model() ->
        {:error, :semantic_model_policy_mismatch}

      request["reasoning_effort"] != Atom.to_string(SemanticAssessment.reasoning_effort()) ->
        {:error, :semantic_reasoning_policy_mismatch}

      not valid_provider_policy?(request) ->
        {:error, :semantic_provider_policy_mismatch}

      true ->
        :ok
    end
  end

  defp source_binding(request, descriptor) do
    if request["source_sha256"] == descriptor["source_sha256"] and
         request["render_sha256"] == descriptor["render_sha256"] and
         request["source_basis"] == descriptor["source_basis"] and
         request["source_artifact_id"] == descriptor["source_artifact_id"],
       do: :ok,
       else: {:error, :semantic_source_binding_mismatch}
  end

  defp prompt_binding(request, source) do
    %{
      "assessment_id" => request["assessment_id"],
      "project_id" => request["project_id"],
      "screenplay_id" => request["screenplay_id"],
      "revision_id" => request["revision_id"],
      "source_sha256" => request["source_sha256"],
      "render_sha256" => request["render_sha256"],
      "source_basis" => request["source_basis"],
      "source_artifact_id" => request["source_artifact_id"] || source["source_artifact_id"],
      "model" => request["model"],
      "reasoning_effort" => request["reasoning_effort"],
      "literal_elements" => source["literal_elements"] || [],
      "limits" => request["limits"] || %{}
    }
  end

  defp valid_provider_policy?(%{
         "service_key" => "deterministic_fixture",
         "provider_family" => "fixture"
       }),
       do: true

  defp valid_provider_policy?(%{"service_key" => "codex", "provider_family" => "codex"}), do: true
  defp valid_provider_policy?(_), do: false

  defp validate_inference_ceiling(request, plan) do
    configured = get_in(request, ["limits", "max_inference_calls"])
    ceiling = 4 * (plan["chunk_count"] || 0) + 2

    if is_integer(configured) and configured > 0 and configured <= ceiling,
      do: :ok,
      else: {:error, :semantic_inference_call_limit_invalid}
  end

  defp validate_returned_models(trace) when is_list(trace) do
    models = Enum.map(trace, &(&1["model"] || &1[:model]))

    cond do
      trace == [] or Enum.any?(models, &is_nil/1) ->
        {:error, :semantic_returned_model_missing}

      mismatch = Enum.find(models, &(&1 != SemanticAssessment.model())) ->
        {:error, {:semantic_returned_model_mismatch, mismatch}}

      true ->
        :ok
    end
  end

  defp returned_model(trace) do
    trace |> Enum.reverse() |> Enum.find_value(& &1["model"])
  end

  defp progress_coverage(plan, completed) do
    chunks = plan["chunks"] || []
    completed = min(max(completed, 0), length(chunks))
    processed = Enum.take(chunks, completed)

    %{
      "chunk_count" => length(chunks),
      "completed_chunks" => completed,
      "source_bytes" => plan["source_bytes"] || 0,
      "processed_bytes" => Enum.reduce(processed, 0, &((&1["payload_bytes"] || 0) + &2)),
      "complete" => completed == length(chunks)
    }
  end

  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason({tag, _}) when is_atom(tag), do: Atom.to_string(tag)
  defp safe_reason(_), do: "semantic_assessment_failed"
end
