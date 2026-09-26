defmodule FountWorkshop.Session do
  @moduledoc "Durable writer sessions with immutable bases, saved successes and explicit pending/failed branch retries."
  alias Fount.Screenplay.Model
  alias Fount.Writing.CanonicalJSON
  alias FountProbe.Budget
  alias FountProbe.Report
  alias FountWorkshop.Candidate
  alias FountWorkshop.Request
  alias FountWorkshop.Store
  alias FountWorkshop.Strategy
  alias FountWorkshop.Writing.Generation
  alias FountWorkshop.Writing.Preparation

  def start(model, request, services, opts \\ []) do
    with {:ok, request} <- Request.validate(model, request),
         :ok <- services(services),
         {:ok, session} <-
           Store.call(services[:store], :save_session, [
             %{
               "id" => Fount.ID.v4(),
               "screenplay_id" => model.id,
               "base_revision_id" => model.revision.id,
               "workflow" => request["workflow"],
               "request" => request,
               "status" => "open",
               "strategies" => [],
               "progress" => %{"branches" => %{}, "report_ids" => [], "spent" => %{}},
               "provenance" => %{
                 "limits" => limits(opts),
                 "implementation" => "creative-workflows-v1"
               }
             }
           ]) do
      execute(model, session, services, opts)
    end
  end

  def resume(id, services, opts \\ []) do
    with {:ok, session} <- Store.call(services[:store], :session, [id]),
         {:ok, model} <-
           Store.call(services[:store], :load_revision, [
             session["screenplay_id"],
             session["base_revision_id"]
           ]),
         :ok <- services(services) do
      opts =
        Enum.reduce(session["provenance"]["limits"] || %{}, opts, fn {key, value}, acc ->
          Keyword.put_new(acc, option_key(key), value)
        end)

      execute(model, session, services, opts)
    end
  end

  def get(id, services) do
    with {:ok, session} <- Store.call(services[:store], :session, [id]) do
      candidates = Store.call(services[:store], :candidates_for_session, [id])

      case candidates do
        {:error, _} = error -> error
        list -> {:ok, Map.put(session, "candidates", list)}
      end
    end
  end

  defp execute(model, session, services, opts) do
    budget =
      Keyword.get(opts, :budget) ||
        Budget.new(Keyword.put(opts, :spent, session["progress"]["spent"] || %{}))

    opts =
      opts |> Keyword.put(:budget, budget) |> Keyword.put(:history_reader, Store.reader(services))

    # Keep explicit room for strategies and actual pages before spending on supporting inspections.
    reserve =
      if session["strategies"] == [],
        do: 1 + 2 * session["request"]["alternatives"],
        else:
          2 *
            length(Keyword.get(opts, :strategy_ids, Enum.map(session["strategies"], & &1["id"])))

    preparation_budget = %{
      budget
      | limits: Map.update!(budget.limits, :inference, &max(&1 - reserve, 0))
    }

    case prepare(model, session, services, Keyword.put(opts, :budget, preparation_budget)) do
      {:ok, context, session} ->
        continue_after_preparation(model, session, context, services, opts, budget)

      {:error, reason, partial} ->
        fail(session, reason, [Model.plain(partial)], services, budget)

      {:error, reason} ->
        fail(session, reason, [], services, budget)
    end
  end

  defp continue_after_preparation(model, session, context, services, opts, budget) do
    case strategies(model, session, context, services, opts) do
      {:ok, session} ->
        selected =
          Keyword.get(
            opts,
            :strategy_ids,
            default_materialization(session["request"], session["strategies"])
          )

        result =
          Enum.reduce_while(session["strategies"], {:ok, session}, fn strategy, state ->
            materialize_strategy(
              strategy,
              state,
              selected,
              model,
              context,
              services,
              opts,
              budget
            )
          end)

        finish(result, services, budget)

      {:error, reason, traces} ->
        fail(session, reason, traces, services, budget)

      {:error, reason} ->
        fail(session, reason, [], services, budget)
    end
  end

  defp materialize_strategy(
         strategy,
         {:ok, state},
         selected,
         model,
         context,
         services,
         opts,
         budget
       ) do
    branch = get_in(state, ["progress", "branches", strategy["id"]])

    if strategy["id"] not in selected or (branch && branch["status"] == "saved") do
      {:cont, {:ok, state}}
    else
      case materialize_one(model, state, strategy, context, services, opts) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        {:error, reason, updated} -> checkpoint_after_failure(updated, reason, services, budget)
      end
    end
  end

  defp checkpoint_after_failure(updated, reason, services, budget) do
    case checkpoint(updated, services, budget) do
      {:ok, saved} ->
        {:cont, {:ok, saved}}

      {:error, save_reason} ->
        {:halt, {:error, {:checkpoint_failed, reason, save_reason}, updated}}
    end
  end

  defp prepare(model, session, services, opts) do
    cached = get_in(session, ["progress", "preparation", "context"])

    if is_map(cached) and not Keyword.get(opts, :reinspect, false),
      do: prepare_cached(model, session, cached, services, opts),
      else: prepare_fresh(model, session, services, opts)
  end

  defp prepare_cached(model, session, cached, services, opts) do
    source_pairs = Enum.map(cached["source_revision_ids"] || [model.revision.id], &{model.id, &1})

    historical_pairs =
      Enum.map(cached["historical_revisions"] || [], &{&1["screenplay_id"], &1["revision_id"]})

    with {:ok, sources} <- load_cached_revisions(services, source_pairs),
         {:ok, historical} <- load_cached_revisions(services, historical_pairs) do
      context = cached_context(cached, sources, historical)

      if get_in(session, ["progress", "preparation", "status"]) == "partial",
        do: retry_cached(model, session, context, services, opts),
        else: {:ok, context, session}
    end
  end

  defp load_cached_revisions(services, pairs) do
    Enum.reduce_while(pairs, {:ok, []}, fn {screenplay_id, revision_id}, {:ok, acc} ->
      case Store.call(services[:store], :load_revision, [screenplay_id, revision_id]) do
        {:ok, source} -> {:cont, {:ok, acc ++ [source]}}
        error -> {:halt, error}
      end
    end)
  end

  defp cached_context(cached, sources, historical) do
    registry =
      if cached["historical"] do
        (sources ++ historical)
        |> Enum.flat_map(
          &(&1.ir.elements ++ &1.ir.scenes ++ &1.ir.dialogue_blocks ++ Map.values(&1.cast))
        )
        |> Map.new(&{&1.id, &1})
      else
        %{}
      end

    context = %{
      data: cached["data"],
      evidence: cached["evidence"],
      selection: cached["selection"],
      reports: [],
      source_models: sources,
      historical_models: historical,
      restore_registry: registry
    }

    if cached["investigation_strategies"],
      do: Map.put(context, :investigation_strategies, cached["investigation_strategies"]),
      else: context
  end

  defp retry_cached(model, session, context, services, opts) do
    if Preparation.retry_requests(model, session["request"], context) == [] do
      {:ok, context, session}
    else
      retry_cached_reports(model, session, context, services, opts)
    end
  end

  defp retry_cached_reports(model, session, context, services, opts) do
    with {:ok, retried} <-
           Preparation.retry_failed(model, session["request"], context, services, opts),
         {:ok, report_ids} <-
           save_reports(retried.reports, session["id"], services, retried.source_models) do
      save_retried_context(session, retried, report_ids, services, opts)
    end
  end

  defp save_retried_context(session, retried, report_ids, services, opts) do
    status =
      if Enum.all?(retried.data["inspections"], &(&1["status"] == "complete")),
        do: "complete",
        else: "partial"

    updated =
      session
      |> put_in(["progress", "preparation", "status"], status)
      |> put_in(["progress", "preparation", "context_sha256"], CanonicalJSON.hash(retried.data))
      |> put_in(["progress", "preparation", "context", "data"], retried.data)
      |> put_in(["progress", "preparation", "context", "evidence"], retried.evidence)
      |> put_in(
        ["progress", "report_ids"],
        Enum.uniq((session["progress"]["report_ids"] || []) ++ report_ids)
      )
      |> put_in(["progress", "spent"], Budget.snapshot(opts[:budget]))

    case Store.call(services[:store], :save_session, [updated]) do
      {:ok, saved} -> {:ok, retried, saved}
      error -> error
    end
  end

  defp prepare_fresh(model, session, services, opts) do
    with {:ok, context} <- Preparation.run(model, session["request"], services, opts),
         {:ok, report_ids} <-
           save_reports(context.reports, session["id"], services, context.source_models) do
      updated =
        session
        |> put_in(
          ["progress", "report_ids"],
          Enum.uniq((session["progress"]["report_ids"] || []) ++ report_ids)
        )
        |> put_in(["progress", "preparation"], %{
          "context_sha256" => CanonicalJSON.hash(context.data),
          "status" =>
            if(Enum.all?(context.reports, &(&1.status == "complete")),
              do: "complete",
              else: "partial"
            ),
          "context" => %{
            "data" => context.data,
            "evidence" => context.evidence,
            "selection" => context.selection,
            "source_revision_ids" => Enum.map(context.source_models, & &1.revision.id),
            "historical_revisions" =>
              Enum.map(
                Map.get(context, :historical_models, []),
                &%{
                  "screenplay_id" => &1.id,
                  "revision_id" => &1.revision.id
                }
              ),
            "historical" => Map.has_key?(context, :restore_registry),
            "investigation_strategies" => Map.get(context, :investigation_strategies)
          }
        })
        |> put_in(["progress", "spent"], Budget.snapshot(opts[:budget]))

      with {:ok, saved} <- Store.call(services[:store], :save_session, [updated]) do
        {:ok, context, saved}
      end
    end
  end

  defp strategies(_, %{"strategies" => [_ | _]} = session, _, _, _), do: {:ok, session}

  defp strategies(model, session, context, services, opts) do
    with {:ok, strategies, traces} <-
           Strategy.generate(model, session["request"], context, services, opts) do
      updated =
        session
        |> Map.put("strategies", strategies)
        |> put_in(["provenance", "strategy_completions"], traces)
        |> put_in(["progress", "spent"], Budget.snapshot(opts[:budget]))

      Store.call(services[:store], :save_session, [updated])
    end
  end

  defp materialize_one(model, session, strategy, context, services, opts) do
    outcome = generate_save(model, session, strategy, context, services, opts)

    outcome =
      repair_if_needed(outcome, %{
        model: model,
        session: session,
        strategy: strategy,
        context: context,
        services: services,
        opts: opts,
        round: 0,
        attempts: [],
        failures: []
      })

    case outcome do
      {:ok, saved, report_ids, attempts, repair_failures} ->
        branch = %{
          "status" => "saved",
          "candidate_id" => saved["id"],
          "report_ids" => report_ids,
          "attempt_candidate_ids" => attempts,
          "repair_failures" => repair_failures,
          "checks" => saved["provenance"]["checks"],
          "needs_writer_review" => true
        }

        updated = put_in(session, ["progress", "branches", strategy["id"]], branch)
        checkpoint(updated, services, opts[:budget])

      error ->
        reason =
          case error do
            {:error, reason, _} -> reason
            {:error, reason} -> reason
            other -> other
          end

        branch = %{
          "status" => "failed",
          "error" => safe_error(reason),
          "attempts" =>
            (get_in(session, ["progress", "branches", strategy["id"], "attempts"]) || 0) + 1
        }

        {:error, reason, put_in(session, ["progress", "branches", strategy["id"]], branch)}
    end
  end

  defp generate_save(model, session, strategy, context, services, opts) do
    with {:ok, candidate} <-
           Generation.propose(model, session["request"], strategy, context, services, opts),
         {:ok, candidate, reports} <- Candidate.check(model, candidate, services, opts),
         {:ok, report_ids} <-
           save_reports(reports, session["id"], services, [
             candidate["screenplay"] | context.source_models
           ]),
         provenance =
           candidate["provenance"]
           |> Map.put("report_ids", report_ids)
           |> Map.put("preparation_report_ids", session["progress"]["report_ids"]),
         {:ok, saved} <-
           Store.call(services[:store], :save_candidate, [
             session["id"],
             Map.put(candidate, "provenance", provenance)
           ]) do
      {:ok, saved, report_ids}
    end
  end

  defp repair_if_needed({:ok, candidate, report_ids}, state) do
    %{
      model: model,
      session: session,
      strategy: strategy,
      context: context,
      services: services,
      opts: opts,
      round: round,
      attempts: prior_attempts,
      failures: failures
    } = state

    attempts = prior_attempts ++ [candidate["id"]]

    failed =
      Enum.filter(
        candidate["provenance"]["checks"] || [],
        &(&1["severity"] == "required" and &1["status"] == "fail")
      )

    if failed != [] and round < Keyword.get(opts, :max_repair_rounds, 1) do
      feedback = %{
        "candidate_id" => candidate["id"],
        "failed_checks" => failed,
        "repair_round" => round + 1
      }

      repair_opts =
        opts
        |> Keyword.put(:repair_feedback, feedback)
        |> Keyword.put(:source_candidate, %{
          "proposal" => Candidate.proposal(candidate),
          "pages" => Fount.Screenplay.to_fountain(candidate["screenplay"], mode: :spec)
        })
        |> Keyword.put(:parent_candidate_id, candidate["id"])

      case generate_save(model, session, strategy, context, services, repair_opts) do
        {:ok, _, _} = repaired ->
          repair_if_needed(repaired, %{state | round: round + 1, attempts: attempts})

        {:error, reason} ->
          {:ok, candidate, report_ids, attempts,
           failures ++
             [
               %{
                 "source_candidate_id" => candidate["id"],
                 "round" => round + 1,
                 "error" => safe_error(reason)
               }
             ]}

        {:error, reason, _} ->
          {:ok, candidate, report_ids, attempts,
           failures ++
             [
               %{
                 "source_candidate_id" => candidate["id"],
                 "round" => round + 1,
                 "error" => safe_error(reason)
               }
             ]}
      end
    else
      {:ok, candidate, report_ids, attempts, failures}
    end
  end

  defp repair_if_needed(error, _state), do: error

  def save_reports(reports, session_id, services, sources \\ []) do
    Enum.reduce_while(reports, {:ok, []}, fn report, {:ok, ids} ->
      models = Enum.uniq_by(sources ++ report.transient_models, & &1.revision.id)

      case Store.call(services[:store], :save_report, [
             Report.persistence(report, session_id),
             [source_models: models]
           ]) do
        {:ok, saved} -> {:cont, {:ok, ids ++ [saved["id"]]}}
        error -> {:halt, error}
      end
    end)
  end

  defp checkpoint(session, services, budget),
    do:
      Store.call(services[:store], :save_session, [
        put_in(session, ["progress", "spent"], Budget.snapshot(budget))
      ])

  defp finish({:error, reason, session}, _, _), do: {:error, reason, session}

  defp finish({:ok, session}, services, budget) do
    branches = Map.values(session["progress"]["branches"])
    failed = Enum.any?(branches, &(&1["status"] == "failed"))
    incomplete_inspections = get_in(session, ["progress", "preparation", "status"]) == "partial"

    status =
      cond do
        failed or incomplete_inspections -> "partial"
        branches == [] -> "strategies_ready"
        true -> "review_ready"
      end

    case checkpoint(Map.put(session, "status", status), services, budget) do
      {:ok, saved} -> if failed, do: {:error, :partial_workflow, saved}, else: {:ok, saved}
      {:error, reason} -> {:error, reason, session}
    end
  end

  defp fail(session, reason, traces, services, budget) do
    updated =
      session
      |> Map.put("status", "partial")
      |> put_in(["progress", "last_error"], safe_error(reason))
      |> put_in(["progress", "last_attempt"], Model.plain(traces))

    case checkpoint(updated, services, budget) do
      {:ok, saved} -> {:error, reason, saved}
      _ -> {:error, reason, updated}
    end
  end

  defp default_materialization(%{"mode" => mode}, _) when mode in ["explore", "diagnose"], do: []

  defp default_materialization(
         %{"workflow" => "investigate", "options" => %{"write_fixes" => false}},
         _
       ),
       do: []

  defp default_materialization(%{"workflow" => "investigate"}, strategies),
    do: strategies |> Enum.take(2) |> Enum.map(& &1["id"])

  defp default_materialization(_, strategies), do: Enum.map(strategies, & &1["id"])
  defp services(%{store: %Store{}, inference: %Inference.Client{}}), do: :ok
  defp services(_), do: {:error, :explicit_store_and_inference_services_required}

  defp safe_error(%Inference.Error{category: category, reason: reason}),
    do: %{
      "code" => "Inference.Error",
      "category" => to_string(category),
      "reason" => to_string(reason)
    }

  defp safe_error(%{__struct__: type}), do: %{"code" => inspect(type)}
  defp safe_error(value), do: %{"code" => inspect(value, limit: 10, printable_limit: 2000)}

  defp limits(opts),
    do:
      Map.new(
        [
          max_inference_calls: 12,
          max_jev_states: 500,
          max_repair_rounds: 1,
          max_investigation_followups: 1,
          max_context_bytes: 100_000
        ],
        fn {k, v} -> {Atom.to_string(k), Keyword.get(opts, k, v)} end
      )

  defp option_key("max_inference_calls"), do: :max_inference_calls
  defp option_key("max_jev_states"), do: :max_jev_states
  defp option_key("max_repair_rounds"), do: :max_repair_rounds
  defp option_key("max_investigation_followups"), do: :max_investigation_followups
  defp option_key("max_context_bytes"), do: :max_context_bytes
end
