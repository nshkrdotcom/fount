defmodule Fount.Observe.Sandbox do
  @moduledoc "Deterministic, data-only fixtures for the public Observe boundary. Missing fixtures are errors, never invented evidence."
  @behaviour Fount.Observe.Provider
  alias Fount.Observe.{Distribution, Error, Provider, ProviderResult, Question}
  alias Fount.Writing.CanonicalJSON

  def new!(fixtures, opts \\ []) when is_map(fixtures) do
    unless Keyword.keys(opts) -- [:order] == [] and Keyword.get(opts, :order, :input) in [:input, :reverse],
      do: raise(ArgumentError, "sandbox order must be :input or :reverse")
    unless match?({:ok, _}, CanonicalJSON.encode(fixtures)),
      do: raise(ArgumentError, "sandbox fixtures must be canonical JSON data")
    %Provider{sensor_id: "sandbox", state: %{fixtures: fixtures, order: Keyword.get(opts, :order, :input)},
      fingerprint: %{"provider" => "sandbox", "model" => "fixture", "stability" => "immutable_exact",
        "fixtures_sha256" => CanonicalJSON.hash(fixtures)}}
  end

  @impl true
  def identity(state, request), do: %{"fixture_sha256" => CanonicalJSON.hash(state.fixtures[request.id])}

  @impl true
  def execute(state, requests, questions, _opts) do
    results = requests |> Enum.with_index() |> Enum.map(fn {request, index} ->
      case decode(state.fixtures[request.id], questions) do
        {:ok, answers} -> %ProviderResult{batch_index: index, answers: answers, metadata: %{"provider" => "sandbox"}}
        {:error, error} -> %ProviderResult{batch_index: index, error: %{error | request_id: request.id}}
      end
    end)
    {:ok, if(state.order == :reverse, do: Enum.reverse(results), else: results)}
  end

  defp decode(fixture, questions) when is_map(fixture) do
    if MapSet.new(Map.keys(fixture)) == MapSet.new(Enum.map(questions, &elem(&1, 0))) do
      Enum.reduce_while(questions, {:ok, %{}}, fn {key, question}, {:ok, acc} ->
        case distribution(fixture[key], question) do
          {:ok, distribution} -> {:cont, {:ok, Map.put(acc, key, distribution)}}
          error -> {:halt, error}
        end
      end)
    else
      {:error, Error.new(:invalid_provider_response, nil, %{"reason" => "fixture_question_mismatch"})}
    end
  end
  defp decode(_, _), do: {:error, Error.new(:provider_unconfigured, nil, %{"reason" => "missing_fixture"})}

  defp distribution(p, %Question{kind: :noul}), do: Distribution.proposition(p)
  defp distribution(%{"probabilities" => probs, "choice" => choice, "confidence" => confidence}, %Question{kind: :choice} = q),
    do: Distribution.choice(probs, Question.domain(q), choice, confidence)
  defp distribution(%{"probabilities" => probs, "score" => score, "confidence" => confidence}, %Question{kind: :score} = q),
    do: Distribution.score(probs, Enum.map(q.levels, &elem(&1, 1)), score, confidence)
  defp distribution(_, _), do: {:error, Error.new(:invalid_provider_response)}
end
