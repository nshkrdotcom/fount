defmodule Fount.Intelligence.Acquisition.Measurements do
  @moduledoc "Shell bridge from source projections to Observe, followed by pure review-policy interpretation."
  alias Fount.Intelligence.Acquisition.InputEvidence
  alias Fount.Intelligence.Capabilities.Interpretation
  alias Fount.Intelligence.Runner.Resources
  alias Fount.Observe.Context
  alias Fount.Observe.{Error, Options, Request}
  alias Fount.Screenplay.Model
  alias Fount.Writing.CanonicalJSON

  def evaluate(provider, inputs, questions, opts \\ [])

  def evaluate(provider, inputs, questions, opts) when is_list(inputs) do
    with :ok <- input_ids(inputs) do
      evaluate_inputs(provider, inputs, questions, opts)
    end
  end

  def evaluate(_, _, _, _), do: {:error, :invalid_measurement_inputs}

  defp evaluate_inputs(provider, inputs, questions, opts) do
    {requests, rejected} =
      Enum.reduce(inputs, {[], %{}}, fn input, {requests, errors} ->
        case request(input, opts) do
          {:ok, request} ->
            {requests ++ [request], errors}

          {:error, reason} ->
            {requests, Map.put(errors, input["id"], failure(input["id"], reason))}
        end
      end)

    observe_opts =
      opts
      |> Keyword.take(Options.allowed())
      |> Keyword.put(:budget, Resources.from_options(opts))

    case Fount.Observe.evaluate(provider, requests, questions, observe_opts) do
      {:ok, batch} ->
        policy = Interpretation.threshold_options(batch.lens_asset)

        measured =
          Map.new(batch.entries, fn entry -> {entry.request_id, decode(entry, policy)} end)

        entries = Enum.map(inputs, &Map.fetch!(Map.merge(measured, rejected), &1["id"]))

        {:ok,
         %{
           "entries" => entries,
           "status" =>
             if(batch.status == :complete and map_size(rejected) == 0,
               do: "complete",
               else: "partial"
             ),
           "errors" =>
             Enum.map(batch.errors, &Error.to_map/1) ++
               Enum.map(Map.values(rejected), & &1["error"]),
           "requested" => length(inputs),
           "scheduled" => batch.scheduled,
           "received" => batch.received,
           "cache_hits" => batch.cache_hits,
           "provider_batches" => batch.provider_batches,
           "elapsed_ms" => batch.elapsed_ms,
           "measurement_spec_sha256" => batch.measurement_spec_sha256,
           "measurement_spec" => batch.measurement_spec,
           "lens_asset" => batch.lens_asset,
           "state_hashes" =>
             Map.new(requests, fn request ->
               {request.id,
                CanonicalJSON.hash(%{
                  "state" => request.input,
                  "context" => Context.to_map(request.context)
                })}
             end)
         }}

      {:error, %Error{} = error} ->
        {:error, Error.to_map(error)}
    end
  end

  defp request(input, opts) do
    model = Map.get(input, :source_model, Keyword.get(opts, :source_model))

    with %Fount.Screenplay{} <- model,
         {:ok, evidence} <- InputEvidence.resolve(model, input) do
      Request.new(model, input["id"], input["state"],
        evidence: evidence,
        target: Map.get(input, "target", %{"kind" => "semantic_subject", "id" => input["id"]}),
        context: Map.get(input, "context", %Context{}),
        provenance: %{"source" => "screenplay_projection"}
      )
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :measurement_source_required}
    end
  end

  defp decode(%{status: :complete} = entry, policy) do
    answers =
      Map.new(entry.observations, fn observation ->
        {observation.kind, Interpretation.answer(observation.result.distribution, policy)}
      end)

    %{
      "input_id" => entry.request_id,
      "status" => "complete",
      "answers" => answers,
      "observations" => Model.plain(entry.observations),
      "provenance" => %{
        "cache_hit" => entry.cache_hit?,
        "measurement_ids" => Enum.map(entry.observations, & &1.result.id)
      }
    }
  end

  defp decode(entry, _), do: failure(entry.request_id, entry.error)

  defp failure(id, %Error{} = error),
    do: %{
      "input_id" => id,
      "status" => "error",
      "error" => Error.to_map(error),
      "answers" => %{},
      "observations" => []
    }

  defp failure(id, reason),
    do: %{
      "input_id" => id,
      "status" => "error",
      "error" => %{"class" => "invalid_source_projection", "reason" => safe_reason(reason)},
      "answers" => %{},
      "observations" => []
    }

  defp safe_reason(reason) when is_atom(reason), do: to_string(reason)
  defp safe_reason(_), do: "invalid_source_projection"

  defp input_ids(inputs) do
    ids = Enum.map(inputs, fn input -> if is_map(input), do: input["id"] end)

    if Enum.all?(ids, &(is_binary(&1) and &1 != "")) and length(ids) == length(Enum.uniq(ids)),
      do: :ok,
      else: {:error, :invalid_or_duplicate_measurement_id}
  end
end
