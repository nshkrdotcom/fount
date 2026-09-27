defmodule Fount.Observe.Lens do
  @moduledoc "Loads installed declarative lens assets and hashes their effective neutral question definitions."
  alias Fount.Observe.{Context, Error, OutputContract, Question, Registry}
  alias Fount.Writing.CanonicalJSON

  def load(id) do
    with true <- Registry.lens?(id),
         {:ok, bytes} <- File.read(Application.app_dir(:fount_observe, "priv/lenses/#{id}.json")),
         {:ok, asset} <- Jason.decode(bytes),
         :ok <- validate_asset(asset, id) do
      {:ok, Map.put(asset, "sha256", CanonicalJSON.hash(asset))}
    else
      _ -> {:error, Error.at(:lens_not_applicable, ["lens_id"])}
    end
  end

  def compile(questions, id \\ nil, projection \\ "explicit_state") do
    with {:ok, questions} <- Question.validate_many(questions),
         {:ok, asset} <- asset(id, projection),
         {:ok, compiled} <- overrides(questions, asset["question_overrides"]) do
      {:ok, compiled, asset}
    end
  end


  @doc "Checks a caller-supplied declaration without loading modules, URLs or credentials."
  def validate(asset) when is_map(asset) do
    raw = Map.delete(asset, "sha256")
    with :ok <- validate_asset(raw, raw["id"]), {:ok, bytes} <- CanonicalJSON.encode(raw),
         true <- byte_size(bytes) <= 65_536 do
      sha = CanonicalJSON.hash(raw)
      if Map.has_key?(asset, "sha256") and asset["sha256"] != sha,
        do: {:error, Error.new(:stale_contract)}, else: {:ok, Map.put(raw, "sha256", sha)}
    else
      _ -> {:error, Error.new(:lens_not_applicable)}
    end
  rescue
    _ -> {:error, Error.new(:lens_not_applicable)}
  end
  def validate(_), do: {:error, Error.new(:lens_not_applicable)}

  @doc false
  def measurement_digest(asset), do: asset
    |> Map.take(~w(id sensor projection context_contract question_overrides output_contract))
    |> CanonicalJSON.hash()

  @doc false
  def restrict_options(asset, opts) do
    requests = Map.get(asset, "resource_policy_request", %{})
    Enum.reduce([:max_states, :max_context_bytes, :max_question_bytes, :max_questions,
                 :total_timeout_ms, :max_concurrency, :max_provider_requests], opts, fn key, acc ->
      case requests[to_string(key)] do
        nil -> acc
        requested -> Keyword.put(acc, key, min(requested, acc[key] || requested))
      end
    end)
  end

  defp valid_resources?(requests) when is_map(requests), do:
    Map.keys(requests) -- ~w(max_states max_context_bytes max_question_bytes max_questions total_timeout_ms max_concurrency max_provider_requests) == [] and
      Enum.all?(requests, fn {_, value} -> is_integer(value) and value > 0 end)
  defp valid_resources?(_), do: false

  def valid_thresholds?(thresholds) when is_map(thresholds) do
    allowed =
      ~w(support_probability unsupported_probability minimum_confidence minimum_margin pass_mass fail_mass)

    Map.keys(thresholds) -- allowed == [] and
      Enum.all?(thresholds, fn {_, value} -> is_number(value) and value >= 0 and value <= 1 end) and
      Map.get(thresholds, "support_probability", 0.8) >
        Map.get(thresholds, "unsupported_probability", 0.2) and
      Map.get(thresholds, "pass_mass", 0.8) > Map.get(thresholds, "fail_mass", 0.2)
  end

  def valid_thresholds?(_), do: false

  defp asset(nil, projection) do
    asset = %{
      "id" => "inline.measurement",
      "sensor" => "system_one",
      "projection" => projection,
      "context_contract" => %{"required" => %{}, "optional" => %{}, "allow_unknown" => false},
      "question_overrides" => [],
      "interpretation_policy" => %{},
      "output_contract" => "observe.answer_set"
    }

    validate(asset)
  end

  defp asset(value, _projection) when is_map(value), do: validate(value)
  defp asset(id, _projection), do: load(id)

  defp validate_asset(asset, id) when is_map(asset) do
    allowed =
      ~w(id description sensor projection context_contract question_overrides interpretation_policy output_contract resource_policy_request)

    valid =
      Map.keys(asset) -- allowed == [] and asset["id"] == id and OutputContract.logical_id?(id) and Registry.sensor?(asset["sensor"]) and
        Registry.projection?(asset["projection"]) and
        asset["output_contract"] == "observe.answer_set" and
        Context.validate_contract(asset["context_contract"]) == :ok and valid_resources?(Map.get(asset, "resource_policy_request", %{})) and
        valid_overrides?(asset["question_overrides"]) and
        valid_thresholds?(Map.get(asset, "interpretation_policy", %{}))

    if valid, do: :ok, else: {:error, :invalid_asset}
  end

  defp validate_asset(_, _), do: {:error, :invalid_asset}

  defp valid_overrides?(specs) when is_list(specs) do
    Enum.all?(specs, fn
      %{"key" => key, "kind" => kind, "instructions" => text} = spec ->
        map_size(spec) == 3 and is_binary(key) and key != "" and kind in ~w(noul choice score) and
          is_binary(text) and String.trim(text) != ""

      _ ->
        false
    end) and length(Enum.uniq_by(specs, & &1["key"])) == length(specs)
  end

  defp valid_overrides?(_), do: false

  defp overrides(questions, specs) do
    indexed = Map.new(specs, &{&1["key"], &1})

    Enum.reduce_while(questions, {:ok, []}, fn {key, q}, {:ok, acc} ->
      case indexed[key] do
        nil ->
          {:cont, {:ok, acc ++ [{key, q}]}}

        spec ->
          override_question(key, q, spec, acc)
      end
    end)
  end

  defp override_question(key, q, spec, acc) do
    if spec["kind"] == to_string(q.kind) do
      {:cont, {:ok, acc ++ [{key, %{q | instructions: spec["instructions"]}}]}}
    else
      {:halt, {:error, Error.at(:lens_not_applicable, ["questions", key])}}
    end
  end
end
