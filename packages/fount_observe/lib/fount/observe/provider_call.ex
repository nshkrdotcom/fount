defmodule Fount.Observe.ProviderCall do
  @moduledoc false
  alias Fount.Observe.{Cancellation, Error, Provider, ProviderResult}

  def run(provider, requests, questions, opts) do
    {:ok, supervisor} = Task.Supervisor.start_link()
    parent = self()
    tag = make_ref()
    try do
      task = Task.Supervisor.async_nolink(supervisor, fn ->
        protected_call(provider, requests, questions, Keyword.put(opts, :observe_progress, {parent, tag}))
      end)
      deadline = System.monotonic_time(:millisecond) + Keyword.fetch!(opts, :total_timeout_ms)
      await(task, deadline, opts[:cancellation], tag, length(requests), [])
    after
      if Process.alive?(supervisor), do: Supervisor.stop(supervisor, :normal)
      drain(tag, [])
    end
  end

  # The sink is created by run/4, not accepted by public Options or declarative assets.
  def deliver(opts, %ProviderResult{} = result) do
    case opts[:observe_progress] do
      {pid, tag} when is_pid(pid) and is_reference(tag) -> send(pid, {:observe_progress, tag, result})
      _ -> :ok
    end
    :ok
  end

  defp protected_call(provider, requests, questions, opts) do
    case Provider.execute(provider, requests, questions, opts) do
      {:ok, results} when is_list(results) -> {:ok, results}
      {:error, %Error{} = error} -> {:error, error}
      _ -> {:error, Error.new(:invalid_provider_response)}
    end
  rescue
    _ -> {:error, Error.new(:provider_unavailable)}
  catch
    _, _ -> {:error, Error.new(:provider_unavailable)}
  end

  defp await(task, deadline, cancellation, tag, count, completed) do
    remaining = deadline - System.monotonic_time(:millisecond)
    cond do
      Cancellation.cancelled?(cancellation) -> stop(task, tag, completed, count, :provider_cancelled)
      remaining <= 0 -> stop(task, tag, completed, count, :provider_timeout)
      true -> receive_result(task, deadline, cancellation, tag, count, completed, min(remaining, 20))
    end
  end

  defp receive_result(task, deadline, cancellation, tag, count, completed, wait) do
    ref = task.ref
    receive do
      {:observe_progress, ^tag, %ProviderResult{} = result} ->
        await(task, deadline, cancellation, tag, count, [result | completed])
      {^ref, {:ok, results}} ->
        Process.demonitor(ref, [:flush])
        {:ok, results}
      {^ref, {:error, %Error{} = error}} ->
        Process.demonitor(ref, [:flush])
        recover(drain(tag, completed), count, error)
      {:DOWN, ^ref, :process, _pid, _reason} ->
        recover(drain(tag, completed), count, Error.new(:provider_unavailable))
    after
      wait -> await(task, deadline, cancellation, tag, count, completed)
    end
  end

  defp stop(task, tag, completed, count, class) do
    Task.shutdown(task, :brutal_kill)
    recover(drain(tag, completed), count, Error.new(class))
  end
  defp drain(tag, acc) do
    receive do
      {:observe_progress, ^tag, %ProviderResult{} = result} -> drain(tag, [result | acc])
    after
      0 -> acc
    end
  end
  defp recover([], _count, error), do: {:error, error}
  defp recover(completed, count, error) do
    present = MapSet.new(Enum.map(completed, & &1.batch_index))
    missing = for index <- 0..(count - 1), not MapSet.member?(present, index),
      do: %ProviderResult{batch_index: index, error: error}
    # Duplicates are intentionally preserved for Association to reject.
    {:ok, Enum.reverse(completed) ++ missing}
  end
end
