defmodule Fount.Observe.DeclarativeLens do
  @moduledoc "Validates constrained project/studio measurement declarations and compiles them only onto Fount.Observe's registered generic measurement machinery."

  alias Fount.Observe.{Error, Lens, Question, Registry}
  alias Fount.Writing.CanonicalJSON

  @allowed ~w(id description trust source kind instructions criteria levels projection output_contract context_contract interpretation_policy resource_policy_request calibration_refs resource_class)
  @trust ~w(studio project third_party)
  @resource_classes ~w(small standard extended)
  @calibrations ~w(identity)
  @forbidden_keys ~w(module function mfa command shell path file endpoint base_url url credentials credential api_key token headers http database query recursion loop tool callback decoder adapter)

  @doc "Returns a validated declaration with a canonical content hash. No module, function, endpoint, credential, file path or tool reference is accepted."
  def validate(declaration) when is_map(declaration) do
    with :ok <- exact_keys(declaration),
         true <- declaration["trust"] in @trust,
         :ok <- source(declaration["source"]),
         true <- declaration["resource_class"] in @resource_classes,
         true <- Registry.projection?(declaration["projection"]),
         true <- declaration["output_contract"] == "observe.answer_set",
         :ok <- calibration_refs(declaration["calibration_refs"] || []),
         {:ok, question} <- question(declaration),
         {:ok, lens_asset} <- lens_asset(declaration),
         {:ok, canonical} <-
           CanonicalJSON.encode(canonical_declaration(declaration, question, lens_asset)),
         true <- byte_size(canonical) <= 65_536 do
      normalized = canonical_declaration(declaration, question, lens_asset)
      {:ok, Map.put(normalized, "sha256", CanonicalJSON.hash(normalized))}
    else
      _ -> {:error, Error.new(:lens_not_applicable)}
    end
  rescue
    _ -> {:error, Error.new(:lens_not_applicable)}
  end

  def validate(_), do: {:error, Error.new(:lens_not_applicable)}

  @doc "Returns the compiled Observe question pair, lens asset and safe execution options for normal Observe preflight/evaluation."
  def compile(declaration) do
    with {:ok, value} <- validate(declaration),
         {:ok, question} <- question(value),
         {:ok, lens_asset} <- lens_asset(value) do
      {:ok, [{value["id"], question}], lens_asset, execution_opts(value)}
    end
  end

  @doc "Returns an inspectable preview without installing or enabling anything."
  def preview(declaration) do
    with {:ok, value} <- validate(declaration),
         {:ok, question} <- question(value),
         {:ok, lens_asset} <- lens_asset(value) do
      {:ok,
       %{
         "id" => value["id"],
         "sha256" => value["sha256"],
         "trust" => value["trust"],
         "source" => value["source"],
         "resource_class" => value["resource_class"],
         "question" => Question.specification(question),
         "lens" => lens_asset,
         "calibration_refs" => value["calibration_refs"],
         "execution_options" =>
           Map.new(execution_opts(value), fn {key, item} -> {to_string(key), item} end),
         "enabled" => false
       }}
    end
  end

  @doc "Installs a validated declaration into an explicit immutable caller-owned catalog. Installation never enables it implicitly."
  def install(catalog, declaration) when is_map(catalog) do
    with {:ok, value} <- validate(declaration),
         false <- Map.has_key?(catalog, value["id"]) do
      {:ok, Map.put(catalog, value["id"], %{"asset" => value, "enabled" => false})}
    else
      true -> {:error, :asset_already_installed}
      error -> error
    end
  end

  def install(_, _), do: {:error, :invalid_asset_catalog}

  def enable(catalog, id), do: set_enabled(catalog, id, true)
  def disable(catalog, id), do: set_enabled(catalog, id, false)

  def fetch(catalog, id) when is_map(catalog) and is_binary(id) do
    case catalog[id] do
      %{"asset" => asset, "enabled" => enabled} -> {:ok, Map.put(asset, "enabled", enabled)}
      _ -> {:error, :asset_not_installed}
    end
  end

  def fetch(_, _), do: {:error, :asset_not_installed}

  @doc "Checks that a caller catalog entry is enabled and still matches a safe validated lens."
  def installed_enabled?(catalog, id) when is_map(catalog) and is_binary(id) do
    case catalog[id] do
      %{"asset" => %{} = asset, "enabled" => true} ->
        raw = Map.take(asset, @allowed)

        case validate(raw) do
          {:ok, validated} ->
            asset["id"] == id and asset == validated

          _ ->
            false
        end

      _ ->
        false
    end
  end

  def installed_enabled?(_, _), do: false

  defp set_enabled(catalog, id, enabled) when is_map(catalog) and is_binary(id) do
    case catalog[id] do
      %{} = entry -> {:ok, Map.put(catalog, id, Map.put(entry, "enabled", enabled))}
      _ -> {:error, :asset_not_installed}
    end
  end

  defp set_enabled(_, _, _), do: {:error, :asset_not_installed}

  defp exact_keys(value) do
    keys = Map.keys(value)

    if keys -- @allowed == [] and required_keys(value) and no_forbidden_nested_keys?(value),
      do: :ok,
      else: {:error, :invalid_declaration}
  end

  defp required_keys(value) do
    Enum.all?(
      ~w(id description trust source kind instructions projection output_contract context_contract interpretation_policy resource_policy_request resource_class),
      fn key ->
        Map.has_key?(value, key)
      end
    ) and is_binary(value["id"]) and value["id"] != "" and is_binary(value["description"]) and
      String.trim(value["description"]) != "" and is_binary(value["instructions"]) and
      String.trim(value["instructions"]) != ""
  end

  defp no_forbidden_nested_keys?(value) when is_map(value) do
    Enum.all?(value, fn {key, nested} ->
      down = key |> to_string() |> String.downcase()
      down not in @forbidden_keys and no_forbidden_nested_keys?(nested)
    end)
  end

  defp no_forbidden_nested_keys?(items) when is_list(items),
    do: Enum.all?(items, &no_forbidden_nested_keys?/1)

  defp no_forbidden_nested_keys?(_), do: true

  defp source(%{"label" => label} = source) when is_binary(label) and label != "" do
    if Map.keys(source) -- ~w(label revision owner) == [] and
         Enum.all?(Map.values(source), &(is_nil(&1) or is_binary(&1))),
       do: :ok,
       else: {:error, :invalid_source}
  end

  defp source(_), do: {:error, :invalid_source}

  defp question(declaration) do
    kind = declaration["kind"]
    instructions = declaration["instructions"]

    value =
      case kind do
        "noul" -> Question.noul(instructions)
        "choice" -> Question.choice(instructions, declaration["criteria"] || [])
        "score" -> Question.score(instructions, declaration["levels"] || [])
        _ -> :invalid
      end

    if match?(%Question{}, value), do: {:ok, value}, else: {:error, :invalid_question}
  rescue
    _ -> {:error, :invalid_question}
  end

  defp lens_asset(declaration) do
    Lens.validate(%{
      "id" => declaration["id"],
      "description" => declaration["description"],
      "sensor" => "system_one",
      "projection" => declaration["projection"],
      "output_contract" => declaration["output_contract"],
      "context_contract" => declaration["context_contract"],
      "question_overrides" => [],
      "interpretation_policy" => declaration["interpretation_policy"],
      "resource_policy_request" => declaration["resource_policy_request"]
    })
  end

  defp calibration_refs(refs) when is_list(refs) do
    if length(refs) == length(Enum.uniq(refs)) and Enum.all?(refs, &(&1 in @calibrations)),
      do: :ok,
      else: {:error, :unsupported_calibration}
  end

  defp calibration_refs(_), do: {:error, :unsupported_calibration}

  defp execution_opts(%{"calibration_refs" => [id]}), do: [calibration: id]
  defp execution_opts(_), do: []

  defp canonical_declaration(declaration, question, lens_asset) do
    %{
      "id" => declaration["id"],
      "description" => declaration["description"],
      "trust" => declaration["trust"],
      "source" => declaration["source"],
      "kind" => declaration["kind"],
      "instructions" => declaration["instructions"],
      "criteria" => declaration["criteria"] || [],
      "levels" => declaration["levels"] || [],
      "projection" => declaration["projection"],
      "output_contract" => declaration["output_contract"],
      "context_contract" => declaration["context_contract"],
      "interpretation_policy" => declaration["interpretation_policy"],
      "resource_policy_request" => declaration["resource_policy_request"],
      "calibration_refs" => declaration["calibration_refs"] || [],
      "resource_class" => declaration["resource_class"],
      "question_specification" => Question.specification(question),
      "lens_measurement_sha256" => Lens.measurement_digest(lens_asset)
    }
  end
end
