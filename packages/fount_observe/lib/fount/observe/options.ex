defmodule Fount.Observe.Options do
  @moduledoc false
  alias Fount.Observe.{Budget, Cancellation, Error}
  alias Fount.Writing.CanonicalJSON
  @defaults [max_states: 500, max_context_bytes: 100_000, max_concurrency: 4,
    task_timeout_ms: 40_000, total_timeout_ms: 120_000, cache_policy: :stable_only]
  @allowed [:model, :extra_body, :retry, :timeout_ms, :attempt_timeout_ms, :task_timeout_ms,
    :max_concurrency, :max_pending, :probability_tolerance, :max_request_bytes, :total_timeout_ms,
    :max_states, :max_context_bytes, :budget, :cache, :privacy_namespace, :lens_id, :cancellation,
    :run_id, :cache_policy]

  def normalize(opts) when is_list(opts) do
    if Keyword.keyword?(opts) and Keyword.keys(opts) -- @allowed == [] do
      opts = Keyword.merge(@defaults, opts)
      opts = Keyword.put_new(opts, :max_pending, opts[:max_concurrency] * 4)
      if valid?(opts), do: {:ok, opts}, else: {:error, Error.at(:invalid_request, ["options"])}
    else
      {:error, Error.at(:invalid_request, ["options"])}
    end
  rescue
    _ -> {:error, Error.at(:invalid_request, ["options"])}
  end
  def normalize(_), do: {:error, Error.at(:invalid_request, ["options"])}
  def allowed, do: @allowed

  def semantic(opts) do
    # Operational limits do not change the measured function. Model-visible extras do.
    opts |> Keyword.take([:model, :extra_body, :probability_tolerance]) |> Map.new(fn {k, v} -> {to_string(k), v} end)
  end

  defp valid?(opts) do
    nonnegative?(opts[:max_states]) and positive?(opts[:max_context_bytes]) and
      is_integer(opts[:max_concurrency]) and opts[:max_concurrency] in 1..1024 and
      is_integer(opts[:max_pending]) and opts[:max_pending] >= opts[:max_concurrency] and opts[:max_pending] <= 10_000 and
      Enum.all?([:task_timeout_ms, :total_timeout_ms], &positive?(opts[&1])) and
      Enum.all?([:timeout_ms, :attempt_timeout_ms, :max_request_bytes], &(is_nil(opts[&1]) or positive?(opts[&1]))) and
      not (not is_nil(opts[:timeout_ms]) and not is_nil(opts[:attempt_timeout_ms])) and
      (is_nil(opts[:model]) or (is_binary(opts[:model]) and String.trim(opts[:model]) != "")) and
      match?({:ok, _}, CanonicalJSON.encode(semantic(opts))) and
      (is_nil(opts[:retry]) or is_boolean(opts[:retry])) and
      (is_nil(opts[:probability_tolerance]) or (is_number(opts[:probability_tolerance]) and opts[:probability_tolerance] >= 0 and opts[:probability_tolerance] <= 0.02)) and
      (is_nil(opts[:budget]) or match?(%Budget{}, opts[:budget])) and
      (is_nil(opts[:cancellation]) or match?(%Cancellation{}, opts[:cancellation])) and
      (is_nil(opts[:run_id]) or (is_binary(opts[:run_id]) and opts[:run_id] != "")) and
      opts[:cache_policy] in [:stable_only, :session] and valid_cache?(opts)
  end
  defp valid_cache?(opts) do
    case opts[:cache] do
      nil -> true
      {module, _handle} when is_atom(module) -> is_binary(opts[:privacy_namespace]) and opts[:privacy_namespace] != ""
      _ -> false
    end
  end
  defp positive?(value), do: is_integer(value) and value > 0
  defp nonnegative?(value), do: is_integer(value) and value >= 0
end
