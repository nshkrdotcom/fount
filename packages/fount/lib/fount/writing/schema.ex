defmodule Fount.Writing.Schema do
  @moduledoc "Validates the shipped screenplay JSON contracts without fetching remote schemas."
  @files ~w(operations.json proposal.schema.json workflow.schema.json)
  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  def load(name) when name in @files do
    name |> then(&Application.app_dir(:fount, "priv/writing_contracts/" <> &1)) |> File.read!() |> Jason.decode!()
  end

  def validate(name, value) when name in @files do
    schema = load(name)
    validate_value(schema, value, schema, "$") |> result()
  end

  def validate(schema, value) when is_map(schema), do: validate_value(schema, value, schema, "$") |> result()
  def validate(_, _), do: {:error, [%{"path" => "$", "reason" => "invalid_schema"}]}

  @doc "Expands only the bundled schema references for a provider request."
  def inline(name) when name in @files, do: name |> load() |> then(&expand(&1, &1))

  defp expand(%{"$ref" => ref} = schema, root) do
    {target, owner} = resolve(ref, root)
    Map.merge(expand(target, owner), expand(Map.delete(schema, "$ref"), root))
  end
  defp expand(map, root) when is_map(map), do: Map.new(map, fn {k, v} -> {k, expand(v, root)} end)
  defp expand(list, root) when is_list(list), do: Enum.map(list, &expand(&1, root))
  defp expand(value, _), do: value

  defp validate_value(true, _, _, _), do: []
  defp validate_value(false, _, _, path), do: error(path, "forbidden")
  defp validate_value(schema, value, root, path) when is_map(schema) do
    ref_errors = case schema["$ref"] do
      nil -> []
      ref -> {target, owner} = resolve(ref, root); validate_value(target, value, owner, path)
    end
    type_errors = if Map.has_key?(schema, "type") and not Enum.any?(List.wrap(schema["type"]), &type?(value, &1)), do: error(path, "type"), else: []
    scalar = []
      |> add(Map.has_key?(schema, "const") and value != schema["const"], path, "const")
      |> add(is_list(schema["enum"]) and value not in schema["enum"], path, "enum")
    unions = Enum.flat_map(~w(allOf anyOf oneOf), fn key ->
      case schema[key] do
        nil -> []
        options ->
          n = Enum.count(options, &(validate_value(&1, value, root, path) == []))
          ok = case key do "allOf" -> n == length(options); "anyOf" -> n > 0; "oneOf" -> n == 1 end
          if ok, do: [], else: error(path, key)
      end
    end)
    negative = if schema["not"] && validate_value(schema["not"], value, root, path) == [], do: error(path, "not"), else: []
    ref_errors ++ type_errors ++ scalar ++ unions ++ negative ++ children(schema, value, root, path)
  end

  defp children(schema, value, root, path) when is_map(value) do
    props = schema["properties"] || %{}
    required = for key <- schema["required"] || [], not Map.has_key?(value, key), do: %{"path" => path <> "." <> key, "reason" => "required"}
    fields = Enum.flat_map(value, fn {key, child} ->
      case Map.fetch(props, key) do
        {:ok, sub} -> validate_value(sub, child, root, path <> "." <> to_string(key))
        :error -> case Map.get(schema, "additionalProperties", true) do
          false -> error(path <> "." <> to_string(key), "unknown_key")
          sub when is_map(sub) -> validate_value(sub, child, root, path <> "." <> to_string(key))
          _ -> []
        end
      end
    end)
    required ++ fields
  end
  defp children(schema, value, root, path) when is_list(value) do
    [] |> add(is_integer(schema["minItems"]) and length(value) < schema["minItems"], path, "minItems")
       |> add(is_integer(schema["maxItems"]) and length(value) > schema["maxItems"], path, "maxItems")
       |> add(schema["uniqueItems"] == true and length(Enum.uniq(value)) != length(value), path, "uniqueItems")
       |> Kernel.++(Enum.flat_map(Enum.with_index(value), fn {item, n} -> validate_value(Map.get(schema, "items", true), item, root, path <> "[#{n}]") end))
  end
  defp children(schema, value, _, path) when is_binary(value) do
    [] |> add(not String.valid?(value), path, "utf8")
       |> add(is_integer(schema["minLength"]) and String.length(value) < schema["minLength"], path, "minLength")
       |> add(is_integer(schema["maxLength"]) and String.length(value) > schema["maxLength"], path, "maxLength")
       |> add(is_binary(schema["pattern"]) and not Regex.match?(Regex.compile!(schema["pattern"]), value), path, "pattern")
       |> add(schema["format"] == "uuid" and not Regex.match?(@uuid, value), path, "uuid")
  end
  defp children(schema, value, _, path) when is_number(value) do
    [] |> add(is_number(schema["minimum"]) and value < schema["minimum"], path, "minimum")
       |> add(is_number(schema["maximum"]) and value > schema["maximum"], path, "maximum")
  end
  defp children(_, _, _, _), do: []

  defp type?(v, "object"), do: is_map(v) and not is_struct(v)
  defp type?(v, "array"), do: is_list(v)
  defp type?(v, "string"), do: is_binary(v)
  defp type?(v, "number"), do: is_number(v)
  defp type?(v, "integer"), do: is_integer(v)
  defp type?(v, "boolean"), do: is_boolean(v)
  defp type?(v, "null"), do: is_nil(v)
  defp type?(_, _), do: false
  defp add(errors, true, path, reason), do: errors ++ error(path, reason)
  defp add(errors, _, _, _), do: errors
  defp error(path, reason), do: [%{"path" => path, "reason" => reason}]
  defp result([]), do: :ok
  defp result(errors), do: {:error, errors}

  defp resolve("#/" <> pointer, root) do
    target = pointer |> String.split("/") |> Enum.reduce(root, fn key, node -> Map.fetch!(node, key |> String.replace("~1", "/") |> String.replace("~0", "~")) end)
    {target, root}
  end
  defp resolve(name, _) when name in @files do
    schema = load(name)
    {schema, schema}
  end
end
