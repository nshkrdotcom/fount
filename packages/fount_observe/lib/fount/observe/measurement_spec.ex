defmodule Fount.Observe.MeasurementSpec do
  @moduledoc false
  alias Fount.Observe.{Calibration, Context, Error, Lens, Options, Question, Registry, Request}
  alias Fount.Writing.CanonicalJSON

  def compile(requests, questions, opts) do
    with {:ok, opts} <- Options.normalize(opts), :ok <- request_ids(requests),
         {:ok, questions, lens} <- Lens.compile(questions, opts[:lens] || opts[:lens_id], projection(requests)),
         opts = Lens.restrict_options(lens, opts),
         {:ok, calibration} <- calibration(opts[:calibration]),
         true <- length(questions) <= opts[:max_questions],
         true <- byte_size(CanonicalJSON.encode!(Question.specifications(questions))) <= opts[:max_question_bytes],
         {:ok, context_digest} <- Context.contract_digest(lens["context_contract"]) do
      opts = if is_integer(opts[:max_provider_requests]), do: Keyword.put(opts, :retry, false), else: opts
      spec = %{"questions" => Question.specifications(questions),
        "lens_sha256" => Lens.measurement_digest(lens),
        "output_contracts" => Enum.map(questions, fn {key, q} ->
          %{"key" => key, "id" => "observe.distribution", "sha256" => Question.output_digest(q)}
        end), "projection_sha256" => Registry.projection_digest(lens["projection"]),
        "context_contract_sha256" => context_digest,
        "calibration_sha256" => if(calibration, do: calibration["sha256"])}
      {:ok, %{questions: questions, lens: lens, opts: opts, calibration: calibration,
        specification: spec, spec_hash: CanonicalJSON.hash(spec),
        execution_hash: CanonicalJSON.hash(Options.semantic(opts))}}
    else
      false -> {:error, Error.new(:state_too_large)}
      {:error, %Error{} = error} -> {:error, error}
      _ -> {:error, Error.new(:invalid_request)}
    end
  rescue
    _ -> {:error, Error.new(:invalid_request)}
  end

  defp calibration(id) when is_binary(id), do: Calibration.load(id)
  defp calibration(asset), do: Calibration.validate(asset)
  defp projection(requests) do
    case requests |> Enum.map(& &1.projection_id) |> Enum.uniq() do
      [id] -> id
      _ -> "explicit_state"
    end
  end
  defp request_ids(requests) when is_list(requests) do
    if Enum.all?(requests, &match?(%Request{}, &1)) do
      ids = Enum.map(requests, & &1.id)
      if Enum.all?(ids, &(is_binary(&1) and &1 != "" and String.valid?(&1))) and
           length(ids) == length(Enum.uniq(ids)), do: :ok, else: invalid()
    else
      invalid()
    end
  end
  defp request_ids(_), do: invalid()
  defp invalid, do: {:error, Error.at(:invalid_request, ["requests"])}
end
