defmodule Fount.Observe.Lens do
  @moduledoc "Loads installed declarative lens assets and hashes their effective neutral question definitions."
  alias Fount.Observe.{Error, Question, Registry}
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

  def compile(questions, id \\ nil) do
    with {:ok, questions} <- Question.validate_many(questions),
         {:ok, asset} <- asset(id),
         {:ok, compiled} <- overrides(questions, asset["question_overrides"]) do
      {:ok, compiled, asset}
    end
  end

  def valid_thresholds?(thresholds) when is_map(thresholds) do
    allowed = ~w(support_probability unsupported_probability minimum_confidence minimum_margin pass_mass fail_mass)
    Map.keys(thresholds) -- allowed == [] and
      Enum.all?(thresholds, fn {_, value} -> is_number(value) and value >= 0 and value <= 1 end) and
      Map.get(thresholds, "support_probability", 0.8) > Map.get(thresholds, "unsupported_probability", 0.2) and
      Map.get(thresholds, "pass_mass", 0.8) > Map.get(thresholds, "fail_mass", 0.2)
  end
  def valid_thresholds?(_), do: false

  defp asset(nil) do
    asset = %{"id" => "inline.measurement", "sensor" => "system_one", "projection" => "explicit_state",
      "context_contract" => %{"required" => %{}, "optional" => %{}, "allow_unknown" => false},
      "question_overrides" => [], "interpretation_policy" => %{}, "output_contract" => "observe.answer_set"}
    {:ok, Map.put(asset, "sha256", CanonicalJSON.hash(asset))}
  end
  defp asset(id), do: load(id)

  defp validate_asset(asset, id) when is_map(asset) do
    allowed = ~w(id description sensor projection context_contract question_overrides interpretation_policy output_contract)
    valid = Map.keys(asset) -- allowed == [] and asset["id"] == id and Registry.sensor?(asset["sensor"]) and
      Registry.projection?(asset["projection"]) and asset["output_contract"] == "observe.answer_set" and
      valid_context?(asset["context_contract"]) and valid_overrides?(asset["question_overrides"]) and
      valid_thresholds?(Map.get(asset, "interpretation_policy", %{}))
    if valid, do: :ok, else: {:error, :invalid_asset}
  end
  defp validate_asset(_, _), do: {:error, :invalid_asset}

  defp valid_context?(%{"required" => required, "optional" => optional, "allow_unknown" => false} = contract),
    do: map_size(contract) == 3 and is_map(required) and is_map(optional) and
      MapSet.disjoint?(MapSet.new(Map.keys(required)), MapSet.new(Map.keys(optional)))
  defp valid_context?(_), do: false

  defp valid_overrides?(specs) when is_list(specs) do
    Enum.all?(specs, fn
      %{"key" => key, "kind" => kind, "instructions" => text} = spec ->
        map_size(spec) == 3 and is_binary(key) and key != "" and kind in ~w(noul choice score) and
          is_binary(text) and String.trim(text) != ""
      _ -> false
    end) and length(Enum.uniq_by(specs, & &1["key"])) == length(specs)
  end
  defp valid_overrides?(_), do: false

  defp overrides(questions, specs) do
    indexed = Map.new(specs, &{&1["key"], &1})
    Enum.reduce_while(questions, {:ok, []}, fn {key, q}, {:ok, acc} ->
      case indexed[key] do
        nil -> {:cont, {:ok, acc ++ [{key, q}]}}
        spec ->
          if spec["kind"] == to_string(q.kind) do
            {:cont, {:ok, acc ++ [{key, %{q | instructions: spec["instructions"]}}]}}
          else
            {:halt, {:error, Error.at(:lens_not_applicable, ["questions", key])}}
          end
      end
    end)
  end
end
