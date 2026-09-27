defmodule Fount.Observe.Resources do
  @moduledoc "Provider-free preflight estimates and actual acquisition accounting. Unknown cost is nil, never a guessed zero."
  alias Fount.Observe.{MeasurementSpec, Request}
  alias Fount.Writing.CanonicalJSON

  def preflight(requests, questions, opts \\ []) do
    with {:ok, plan} <- MeasurementSpec.compile(requests, questions, opts), do: {:ok, estimate(requests, plan)}
  end

  @doc false
  def estimate(requests, plan) do
    sizes = Enum.map(requests, fn request ->
      try do
        %{"request_id" => request.id, "semantic_input_bytes" => byte_size(Request.semantic_input(request))}
      rescue
        _ -> %{"request_id" => request.id, "semantic_input_bytes" => nil}
      end
    end)
    %{"targets" => length(requests), "questions" => length(plan.questions), "states" => sizes,
      "measurement_spec_bytes" => byte_size(CanonicalJSON.encode!(plan.specification)),
      "provider_requests_before_retries_estimate" => Enum.min([length(requests), plan.opts[:max_states], plan.opts[:max_provider_requests] || length(requests)]),
      "reuse_estimate" => nil, "wire_request_bytes" => nil, "hosted_cost" => nil,
      "caps" => Map.new(Keyword.take(plan.opts, [:max_states, :max_context_bytes, :max_question_bytes,
        :max_questions, :max_request_bytes, :max_provider_requests, :total_timeout_ms, :max_concurrency]),
        fn {k, v} -> {to_string(k), v} end),
      "limitations" => ["No provider dispatch or budget reservation occurs during preflight.",
        "Wire size is enforced by the SDK; semantic byte counts are not wire byte counts.",
        "Retries and cache misses are unknown until execution."]}
  end

  @doc false
  def actual(provider, entries, scheduled, budget) do
    remote = match?(%{sensor_id: "system_one"}, provider)
    metadata = for entry <- entries, entry.status == :complete and not entry.cache_hit?,
      observation = List.first(entry.observations), not is_nil(observation),
      do: observation.result.metadata["provider"] || %{}
    retries = Enum.map(metadata, &Map.get(&1, "retries"))
    retry_count = if remote and length(metadata) == scheduled and Enum.all?(retries, &is_integer/1),
      do: Enum.sum(retries), else: nil
    %{"scheduled_states" => scheduled, "successful_states" => length(metadata),
      "cache_hits" => Enum.count(entries, & &1.cache_hit?),
      "provider_requests" => if(remote, do: if(retry_count, do: scheduled + retry_count), else: 0),
      "initial_provider_requests_scheduled" => if(remote, do: scheduled, else: 0),
      "reported_retries" => retry_count, "hosted_cost" => nil,
      "usage_reported" => Enum.map(metadata, &Map.get(&1, "usage")) |> Enum.reject(&is_nil/1),
      "budget" => Fount.Observe.Budget.snapshot(budget)}
  end
end
