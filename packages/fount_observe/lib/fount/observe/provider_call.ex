defmodule Fount.Observe.ProviderCall do
  @moduledoc false
  alias Fount.Observe.{Cancellation, Error, Provider}

  def run(provider, requests, questions, opts) do
    {:ok, supervisor} = Task.Supervisor.start_link()
    try do
      task = Task.Supervisor.async_nolink(supervisor, fn -> protected_call(provider, requests, questions, opts) end)
      deadline = System.monotonic_time(:millisecond) + Keyword.fetch!(opts, :total_timeout_ms)
      await(task, deadline, Keyword.get(opts, :cancellation))
    after
      if Process.alive?(supervisor), do: Supervisor.stop(supervisor, :normal)
    end
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

  defp await(task, deadline, cancellation) do
    remaining = deadline - System.monotonic_time(:millisecond)
    cond do
      Cancellation.cancelled?(cancellation) ->
        Task.shutdown(task, :brutal_kill)
        {:error, Error.new(:provider_cancelled)}
      remaining <= 0 ->
        Task.shutdown(task, :brutal_kill)
        {:error, Error.new(:provider_timeout)}
      true ->
        case Task.yield(task, min(remaining, 20)) do
          {:ok, result} -> result
          {:exit, _} -> {:error, Error.new(:provider_unavailable)}
          nil -> await(task, deadline, cancellation)
        end
    end
  end
end
