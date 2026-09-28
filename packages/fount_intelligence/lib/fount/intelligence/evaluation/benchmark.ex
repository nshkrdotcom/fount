defmodule Fount.Intelligence.Evaluation.Benchmark do
  @moduledoc """
  Frozen current-contract MeasurementResult/Observation fixtures for provider-free reasoning tests.

  A contract change is a visible stale-fixture failure. This module has no compatibility
  decoder; regeneration requires a new current MeasurementResult and Observation.
  """

  alias Fount.Observe.{MeasurementResult, Observation, OutputContract, Question}
  alias Fount.Screenplay.Model
  alias Fount.Writing.CanonicalJSON

  @format "fount.evaluation.fixture"

  @spec freeze(String.t(), Question.t(), MeasurementResult.t(), Observation.t(), map(), keyword()) ::
          {:ok, map()} | {:error, atom()}
  def freeze(
        fixture_id,
        %Question{} = question,
        %MeasurementResult{} = result,
        %Observation{} = observation,
        expected,
        opts \\ []
      )
      when is_binary(fixture_id) and fixture_id != "" and is_map(expected) do
    contract = Question.output_contract(question)

    with :ok <- OutputContract.validate(contract),
         true <- result.output_contract_id == contract["id"],
         true <- result.output_contract_sha256 == contract["sha256"],
         true <- observation.result.id == result.id do
      body = %{
        "format" => @format,
        "fixture_id" => fixture_id,
        "evidence_level" => Keyword.get(opts, :evidence_level, "synthetic"),
        "question" => Question.specification(question),
        "output_contract" => contract,
        "measurement_result" => Model.plain(result),
        "observation" => Model.plain(observation),
        "expected_reasoning" => Model.plain(expected),
        "regression_tags" => Enum.map(Keyword.get(opts, :regression_tags, []), &to_string/1)
      }

      {:ok, Map.put(body, "fixture_sha256", CanonicalJSON.hash(body))}
    else
      _ -> {:error, :incompatible_current_contract_fixture}
    end
  rescue
    _ -> {:error, :invalid_benchmark_fixture}
  end

  @spec validate(map(), Question.t()) :: :ok | {:error, map() | atom()}
  def validate(fixture, %Question{} = current_question) when is_map(fixture) do
    with :ok <- validate_integrity(fixture),
         current <- Question.output_contract(current_question),
         true <- fixture["output_contract"] == current do
      :ok
    else
      false -> stale(fixture, Question.output_contract(current_question))
      {:error, _} = error -> error
    end
  rescue
    _ -> {:error, :invalid_benchmark_fixture}
  end

  def validate(_, _), do: {:error, :invalid_benchmark_fixture}

  @spec regeneration_plan(map(), Question.t()) :: {:ok, map()} | {:error, atom()}
  def regeneration_plan(fixture, %Question{} = current_question) when is_map(fixture) do
    current = Question.output_contract(current_question)

    with :ok <- validate_hash_only(fixture),
         :ok <- OutputContract.validate(current) do
      stale? = fixture["output_contract"] != current

      {:ok,
       %{
         "status" => if(stale?, do: "regeneration_required", else: "current"),
         "fixture_id" => fixture["fixture_id"],
         "old_output_contract_sha256" => get_in(fixture, ["output_contract", "sha256"]),
         "new_output_contract_sha256" => current["sha256"],
         "steps" =>
           if(stale?,
             do: [
               "rerun the current measurement question to produce a new MeasurementResult",
               "materialize a new current-revision Observation with exact evidence/provenance",
               "rerun the provider-free reasoning benchmark and review expected reasoning",
               "call Benchmark.freeze/6 and replace the old fixture explicitly"
             ],
             else: []
           ),
         "compatibility_decode" => false
       }}
    end
  end

  def regeneration_plan(_, _), do: {:error, :invalid_benchmark_fixture}

  defp validate_integrity(fixture) do
    required =
      ~w(format fixture_id evidence_level question output_contract measurement_result observation expected_reasoning regression_tags fixture_sha256)

    with true <- fixture["format"] == @format,
         true <- required -- Map.keys(fixture) == [],
         :ok <- validate_hash_only(fixture),
         :ok <- OutputContract.validate(fixture["output_contract"]),
         true <-
           get_in(fixture, ["measurement_result", "output_contract_id"]) ==
             get_in(fixture, ["output_contract", "id"]),
         true <-
           get_in(fixture, ["measurement_result", "output_contract_sha256"]) ==
             get_in(fixture, ["output_contract", "sha256"]),
         true <-
           get_in(fixture, ["observation", "result", "id"]) ==
             get_in(fixture, ["measurement_result", "id"]) do
      :ok
    else
      _ -> {:error, :invalid_benchmark_fixture}
    end
  end

  defp validate_hash_only(fixture) do
    hash = fixture["fixture_sha256"]
    body = Map.delete(fixture, "fixture_sha256")

    if is_binary(hash) and hash == CanonicalJSON.hash(body),
      do: :ok,
      else: {:error, :invalid_fixture_digest}
  end

  defp stale(fixture, current) do
    {:error,
     %{
       "reason" => "stale_output_contract_fixture",
       "fixture_id" => fixture["fixture_id"],
       "fixture_output_contract_sha256" => get_in(fixture, ["output_contract", "sha256"]),
       "current_output_contract_sha256" => current["sha256"],
       "regeneration_required" => true,
       "compatibility_decode" => false
     }}
  end
end
