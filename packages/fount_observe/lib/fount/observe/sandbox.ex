defmodule Fount.Observe.Sandbox do
  @moduledoc "Deterministic, data-only fixtures for the public Observe boundary. Missing fixtures are errors, never invented evidence."
  @behaviour Fount.Observe.Provider
  alias Fount.Observe.{Distribution, Error, Provider, ProviderResult, Question, Registry, Request}
  alias Fount.Writing.CanonicalJSON

  def new!(fixtures, opts \\ []) when is_map(fixtures) do
    unless Keyword.keys(opts) -- [:order] == [] and
             Keyword.get(opts, :order, :input) in [:input, :reverse],
           do: raise(ArgumentError, "sandbox order must be :input or :reverse")

    unless match?({:ok, _}, CanonicalJSON.encode(fixtures)),
      do: raise(ArgumentError, "sandbox fixtures must be canonical JSON data")

    %Provider{
      sensor_id: "sandbox",
      state: %{fixtures: fixtures, order: Keyword.get(opts, :order, :input)},
      fingerprint: %{
        "provider" => "sandbox",
        "model" => "fixture",
        "stability" => "immutable_exact",
        "fixtures_sha256" => CanonicalJSON.hash(fixtures)
      }
    }
  end

  @impl true

  def identity(%{binding: :semantic} = state, request) do
    input = Request.input_hash(request)
    fixtures = Enum.filter(state.fixtures, fn {_, record} -> record["input_sha256"] == input end)
      |> Enum.map(&elem(&1, 1)) |> Enum.sort_by(& &1["questions_sha256"])
    %{"fixture_sha256" => CanonicalJSON.hash(fixtures)}
  end
  def identity(state, request), do: %{"fixture_sha256" => CanonicalJSON.hash(state.fixtures[request.id])}


  @impl true
  def execute(state, requests, questions, _opts) do
    results =
      requests
      |> Enum.with_index()
      |> Enum.map(fn {request, index} ->
        case resolve(state, request, questions) do
          {:ok, answers} ->
            %ProviderResult{
              batch_index: index,
              answers: answers,
              metadata: %{"provider" => "sandbox"}
            }

          {:error, error} ->
            %ProviderResult{batch_index: index, error: %{error | request_id: request.id}}
        end
      end)

    {:ok, if(state.order == :reverse, do: Enum.reverse(results), else: results)}
  end


  @doc "Creates a serializable fixture bound to semantic bytes, question semantics and output contracts."
  def fixture(%Request{} = request, questions, answers) do
    with :ok <- Request.validate_envelope(request), {:ok, questions} <- Question.validate_many(questions),
         {:ok, _} <- decode(answers, questions) do
      {:ok, %{"input_sha256" => Request.input_hash(request),
        "questions_sha256" => CanonicalJSON.hash(Question.specifications(questions)),
        "projection_id" => request.projection_id, "answers" => answers,
        "output_contracts" => contracts(questions)}}
    end
  rescue
    _ -> {:error, Error.new(:invalid_request)}
  end

  @doc "Loads a local, data-only fixture packet. No provider modules, URLs, secrets or executable terms are accepted."
  def load(path, opts \\ []) do
    limit = Keyword.get(opts, :max_bytes, 1_048_576)
    with true <- Keyword.keyword?(opts) and Keyword.keys(opts) -- [:max_bytes, :order] == [],
         true <- is_integer(limit) and limit > 0 and limit <= 16_777_216,
         true <- Keyword.get(opts, :order, :input) in [:input, :reverse],
         {:ok, %{type: :regular, size: size}} <- File.lstat(path), true <- size <= limit,
         {:ok, bytes} <- File.open(path, [:read, :binary], &IO.binread(&1, limit + 1)),
         true <- is_binary(bytes) and byte_size(bytes) <= limit,
         {:ok, packet} <- Jason.decode(bytes), :ok <- validate_packet(packet) do
      fixtures = Map.new(packet["fixtures"], &{fixture_key(&1), &1})
      if map_size(fixtures) == length(packet["fixtures"]) do
        {:ok, %Provider{sensor_id: "sandbox",
          state: %{fixtures: fixtures, binding: :semantic, order: Keyword.get(opts, :order, :input)},
          fingerprint: %{"provider" => "sandbox", "model" => "fixture", "stability" => "immutable_exact",
            "fixtures_sha256" => CanonicalJSON.hash(packet)}}}
      else
        {:error, Error.new(:invalid_request, nil, %{"reason" => "duplicate_fixture"})}
      end
    else
      _ -> {:error, Error.new(:invalid_request, nil, %{"reason" => "invalid_fixture_packet"})}
    end
  rescue
    _ -> {:error, Error.new(:invalid_request, nil, %{"reason" => "invalid_fixture_packet"})}
  end

  defp validate_packet(%{"id" => id, "fixtures" => fixtures} = packet) do
    valid = map_size(packet) == 2 and Fount.Observe.OutputContract.logical_id?(id) and
      is_list(fixtures) and length(fixtures) <= 2000 and
      Enum.all?(fixtures, fn f -> is_map(f) and
        Enum.sort(Map.keys(f)) == Enum.sort(~w(input_sha256 questions_sha256 projection_id answers output_contracts)) and
        digest?(f["input_sha256"]) and digest?(f["questions_sha256"]) and
        Registry.projection?(f["projection_id"]) and is_map(f["answers"]) and
        valid_contracts?(f["output_contracts"])
      end)
    if valid, do: :ok, else: {:error, :invalid_fixture}
  end
  defp validate_packet(_), do: {:error, :invalid_fixture}
  defp valid_contracts?(contracts) when is_list(contracts) and contracts != [] do
    Enum.all?(contracts, fn
      %{"key" => key, "sha256" => sha} = c -> map_size(c) == 2 and is_binary(key) and key != "" and digest?(sha)
      _ -> false
    end) and length(Enum.uniq_by(contracts, & &1["key"])) == length(contracts)
  end
  defp valid_contracts?(_), do: false
  defp digest?(value), do: is_binary(value) and Regex.match?(~r/^[0-9a-f]{64}$/, value)
  defp fixture_key(f), do: {f["input_sha256"], f["questions_sha256"], f["projection_id"]}
  defp contracts(questions), do: Enum.map(questions, fn {key, q} -> %{"key" => key, "sha256" => Question.output_digest(q)} end)

  defp resolve(%{binding: :semantic} = state, request, questions) do
    key = {Request.input_hash(request), CanonicalJSON.hash(Question.specifications(questions)), request.projection_id}
    case state.fixtures[key] do
      nil -> decode(nil, questions)
      fixture ->
        if fixture["output_contracts"] == contracts(questions),
          do: decode(fixture["answers"], questions), else: {:error, Error.new(:stale_contract)}
    end
  end
  defp resolve(state, request, questions), do: decode(state.fixtures[request.id], questions)

  defp decode(fixture, questions) when is_map(fixture) do
    if MapSet.new(Map.keys(fixture)) == MapSet.new(Enum.map(questions, &elem(&1, 0))) do
      decode_questions(fixture, questions)
    else
      {:error,
       Error.new(:invalid_provider_response, nil, %{"reason" => "fixture_question_mismatch"})}
    end
  end

  defp decode(_, _),
    do: {:error, Error.new(:provider_unconfigured, nil, %{"reason" => "missing_fixture"})}

  defp decode_questions(fixture, questions) do
    Enum.reduce_while(questions, {:ok, %{}}, fn {key, question}, {:ok, acc} ->
      case distribution(fixture[key], question) do
        {:ok, distribution} -> {:cont, {:ok, Map.put(acc, key, distribution)}}
        error -> {:halt, error}
      end
    end)
  end

  defp distribution(p, %Question{kind: :noul}), do: Distribution.proposition(p)

  defp distribution(
         %{"probabilities" => probs, "choice" => choice, "confidence" => confidence},
         %Question{kind: :choice} = q
       ),
       do: Distribution.choice(probs, Question.domain(q), choice, confidence)

  defp distribution(
         %{"probabilities" => probs, "score" => score, "confidence" => confidence},
         %Question{kind: :score} = q
       ),
       do: Distribution.score(probs, Enum.map(q.levels, &elem(&1, 1)), score, confidence)

  defp distribution(_, _), do: {:error, Error.new(:invalid_provider_response)}
end
