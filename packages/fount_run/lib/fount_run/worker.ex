defmodule FountRun.Worker do
  @moduledoc "Configurable poller for one Run. Hosts may supervise zero or more workers."
  use GenServer

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  @impl true
  def init(opts) do
    state = %{
      repo: Keyword.fetch!(opts, :repo),
      run_id: Keyword.fetch!(opts, :run_id),
      context: Keyword.fetch!(opts, :context),
      interval_ms: Keyword.get(opts, :interval_ms, 1_000),
      step_opts:
        opts
        |> Keyword.get(:step_opts, [])
        |> Keyword.put_new(:worker_id, Keyword.get(opts, :worker_id, worker_id()))
    }

    send(self(), :poll)
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    result = FountRun.step(state.repo, state.run_id, state.context, state.step_opts)
    emit(result, state.run_id)
    Process.send_after(self(), :poll, state.interval_ms)
    {:noreply, state}
  end

  defp emit({:ok, _}, run_id),
    do:
      :telemetry.execute([:fount_run, :worker, :step], %{count: 1}, %{status: :ok, run_id: run_id})

  defp emit({:error, reason}, run_id)
       when reason in [:no_work, :busy, :pause_requested, :stop_requested],
       do:
         :telemetry.execute([:fount_run, :worker, :idle], %{count: 1}, %{
           status: reason,
           run_id: run_id
         })

  defp emit({:error, reason}, run_id),
    do:
      :telemetry.execute([:fount_run, :worker, :step], %{count: 1}, %{
        status: :error,
        reason: reason_tag(reason),
        run_id: run_id
      })

  defp reason_tag(reason) when is_atom(reason), do: reason
  defp reason_tag({reason, _}) when is_atom(reason), do: reason
  defp reason_tag(_), do: :error

  defp worker_id,
    do:
      "worker:" <>
        Atom.to_string(node()) <> ":" <> Integer.to_string(System.unique_integer([:positive]))
end
