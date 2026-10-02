defmodule FountRun do
  @moduledoc """
  Durable, policy-aware headless screenplay runs.

  Phase 05 completes the headless surface: exact decisions, plan and policy
  steering, pause/resume/stop, stale-base rebase, canonical approval through
  Core, candidate-only completion, and durable artifact delivery. A host still
  owns authentication, Repo startup, services and artifact-root configuration.
  """

  alias FountRun.{ActorContext, Control, DecisionCommand, DeliveryBundle, Persistence}

  @spec migrations_path() :: String.t()
  def migrations_path, do: Application.app_dir(:fount_run, "priv/repo/migrations")

  def start_run(repo, attrs, actor_context, opts \\ []) do
    repo
    |> Persistence.start_run(attrs, actor_context, opts)
    |> emit(:start_run)
  end

  def get_run(repo, run_id, actor_context) do
    repo
    |> Persistence.get_run(run_id, actor_context)
    |> emit(:get_run)
  end

  def list_runs(repo, filter, actor_context) do
    repo
    |> Persistence.list_runs(filter, actor_context)
    |> emit(:list_runs)
  end

  @doc "Creates one explicit durable operation. Normal screenplay stages schedule their own successors."
  def enqueue_step(repo, run_id, attrs, actor_context) do
    repo
    |> Persistence.create_step(run_id, attrs, actor_context)
    |> emit(:enqueue_step)
  end

  @doc """
  Claims and executes at most one durable operation.

  The documented form accepts a trusted services map containing
  `:actor_context` plus stage services such as `:inference`, optional trusted
  `:observe`, `:approval_context` and `:approval_callback`. The explicit
  ActorContext form remains supported for Phase-03/04 workers.
  """
  def step(repo, run_id, services_or_context, opts \\ [])

  def step(repo, run_id, %ActorContext{} = context, opts) when is_list(opts) do
    repo
    |> FountRun.Engine.step(run_id, context, opts)
    |> emit(:step)
  end

  def step(repo, run_id, services, opts)
      when (is_map(services) or is_list(services)) and is_list(opts) do
    services = if is_list(services), do: Map.new(services), else: services

    case Map.get(services, :actor_context) || Map.get(services, "actor_context") do
      %ActorContext{} = context ->
        case normalize_services(services) do
          {:ok, service_opts} ->
            repo
            |> FountRun.Engine.step(run_id, context, Keyword.merge(service_opts, opts))
            |> emit(:step)

          {:error, reason} ->
            emit({:error, reason}, :step)
        end

      _ ->
        emit({:error, :actor_context_required}, :step)
    end
  end

  def step(_repo, _run_id, _services, _opts), do: {:error, :invalid_services}

  @doc "Resolves an exact persisted decision. Final approval is one typed decision kind on this path."
  def submit_decision(repo, decision_id, response, actor_context) do
    repo
    |> DecisionCommand.submit(decision_id, response, actor_context)
    |> emit(:submit_decision)
  end

  @doc "Appends a complete same-base/scope plan snapshot or creates a linked successor run."
  def update_plan(repo, run_id, plan, actor_context, opts \\ []) do
    repo
    |> Control.update_plan(run_id, plan, actor_context, opts)
    |> emit(:update_plan)
  end

  @doc "Appends a complete effective policy snapshot and fences work bound to the prior version."
  def update_policy(repo, run_id, policy, actor_context, opts \\ []) do
    repo
    |> Control.update_policy(run_id, policy, actor_context, opts)
    |> emit(:update_policy)
  end

  def pause_run(repo, run_id, actor_context) do
    repo
    |> Control.pause(run_id, actor_context)
    |> emit(:pause_run)
  end

  def resume_run(repo, run_id, actor_context) do
    repo
    |> Control.resume(run_id, actor_context)
    |> emit(:resume_run)
  end

  def stop_run(repo, run_id, actor_context) do
    repo
    |> Control.stop(run_id, actor_context)
    |> emit(:stop_run)
  end

  @doc "Convenience wrapper for one exact final-approval decision; it delegates to submit_decision."
  def approve_run(repo, run_id, response, actor_context) do
    repo
    |> DecisionCommand.approve_run(run_id, response, actor_context)
    |> emit(:approve_run)
  end

  @doc "Exports the selected candidate or stored accepted revision under the configured artifact root."
  def deliver(repo, run_id, destination, actor_context, opts \\ []) do
    repo
    |> DeliveryBundle.deliver(run_id, destination, actor_context, opts)
    |> emit(:deliver)
  end

  @doc "Returns persisted progress, decisions, approval attempts, deliveries and safe resource usage."
  def progress(repo, run_id, actor_context) do
    repo
    |> FountRun.ExecutionStore.progress(run_id, actor_context)
    |> emit(:progress)
  end

  @service_keys ~w(inference observe semantic_store approval_context approval_callback approval_reconciler registry worker_id lease_ms heartbeat_ms fault_injector)a

  defp normalize_services(services) do
    Enum.reduce_while(services, {:ok, []}, fn
      {key, _value}, {:ok, acc} when key in [:actor_context, "actor_context"] ->
        {:cont, {:ok, acc}}

      {key, value}, {:ok, acc} ->
        case normalize_service_key(key) do
          {:ok, normalized} -> {:cont, {:ok, [{normalized, value} | acc]}}
          :error -> {:halt, {:error, :invalid_service_key}}
        end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp normalize_service_key(key) when is_atom(key) and key in @service_keys, do: {:ok, key}

  defp normalize_service_key(key) when is_binary(key) do
    case Enum.find(@service_keys, &(Atom.to_string(&1) == key)) do
      nil -> :error
      atom -> {:ok, atom}
    end
  end

  defp normalize_service_key(_), do: :error

  defp emit({:ok, _value} = result, operation) do
    :telemetry.execute([:fount_run, operation], %{system_time: System.system_time()}, %{
      status: :ok
    })

    result
  end

  defp emit({:error, reason} = result, operation) do
    :telemetry.execute([:fount_run, operation], %{system_time: System.system_time()}, %{
      status: :error,
      reason: reason_tag(reason)
    })

    result
  end

  defp emit({:partial, reason, _details} = result, operation) do
    :telemetry.execute([:fount_run, operation], %{system_time: System.system_time()}, %{
      status: :partial,
      reason: reason_tag(reason)
    })

    result
  end

  defp reason_tag(reason) when is_atom(reason), do: reason
  defp reason_tag({reason, _detail}) when is_atom(reason), do: reason
  defp reason_tag(_reason), do: :error
end
