defmodule FountRun.PipelineRequest do
  @moduledoc false

  alias FountRun.ClosedMap

  @keys ~w(kind workshop_request semantic_request semantic_runtime investigation_request investigation_session_id strategy_session_id selected_strategy_ids decision_id candidate_ids source_candidate_id finding report_ids uncertainty lineage check_set_fingerprint)
  @uuid_keys ~w(investigation_session_id strategy_session_id decision_id source_candidate_id)

  @semantic_keys ~w(assessment_id project_id screenplay_id revision_id source_artifact_id source_sha256 render_sha256 schema_version prompt_version model reasoning_effort provider_family service_key command_id limits source_basis)

  def validate(value) do
    with {:ok, value} <- ClosedMap.normalize(value, @keys) do
      case Map.get(value, "kind") do
        "screenplay_v1" -> validate_screenplay(value)
        "semantic_import_v1" -> validate_semantic(value)
        _ -> {:error, :invalid_pipeline_request_kind}
      end
    end
  end

  def new(workshop_request) when is_map(workshop_request),
    do: validate(%{"kind" => "screenplay_v1", "workshop_request" => workshop_request})

  def semantic(semantic_request) when is_map(semantic_request),
    do: validate(%{"kind" => "semantic_import_v1", "semantic_request" => semantic_request})

  defp validate_screenplay(value) do
    with nil <- Map.get(value, "semantic_request"),
         nil <- Map.get(value, "semantic_runtime"),
         request when is_map(request) <- Map.get(value, "workshop_request"),
         true <- ClosedMap.json?(request),
         :ok <- optional_map(value, "investigation_request"),
         :ok <- validate_uuids(value),
         :ok <- optional_strings(value, "selected_strategy_ids"),
         :ok <- optional_strings(value, "candidate_ids"),
         :ok <- optional_strings(value, "report_ids"),
         :ok <- optional_json_list(value, "uncertainty"),
         :ok <- optional_json_list(value, "lineage"),
         :ok <- optional_string(value, "finding"),
         :ok <- optional_hash(value, "check_set_fingerprint") do
      {:ok, value}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_screenplay_pipeline_request}
    end
  end

  defp validate_semantic(value) do
    with true <- Enum.all?(Map.keys(value), &(&1 in ~w(kind semantic_request semantic_runtime))),
         nil <- Map.get(value, "workshop_request"),
         request when is_map(request) <- Map.get(value, "semantic_request"),
         {:ok, request} <- ClosedMap.normalize(request, @semantic_keys),
         true <- ClosedMap.json?(request),
         :ok <- optional_map(value, "semantic_runtime"),
         true <-
           Enum.all?(
             ~w(assessment_id project_id screenplay_id revision_id command_id source_sha256 render_sha256 schema_version prompt_version model reasoning_effort provider_family service_key source_basis),
             &ClosedMap.nonempty_string(request[&1])
           ),
         true <- valid_optional_uuid?(request["assessment_id"]),
         true <- valid_optional_uuid?(request["project_id"]),
         true <- valid_optional_uuid?(request["screenplay_id"]),
         true <- valid_optional_uuid?(request["revision_id"]),
         true <- valid_optional_uuid?(request["source_artifact_id"]),
         :ok <- optional_hash(request, "source_sha256"),
         :ok <- optional_hash(request, "render_sha256"),
         limits when is_map(limits) <- request["limits"],
         true <- ClosedMap.json?(limits),
         {:ok, _resolved_limits} <- FountWorkshop.SemanticAssessment.validate_limits(limits) do
      {:ok, Map.put(value, "semantic_request", request)}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_semantic_pipeline_request}
    end
  end

  def advance(value, attrs) when is_map(attrs) do
    with {:ok, value} <- validate(value) do
      value
      |> Map.merge(stringify_keys(attrs))
      |> validate()
    end
  end

  defp validate_uuids(value) do
    Enum.reduce_while(@uuid_keys, :ok, fn key, :ok ->
      if valid_optional_uuid?(Map.get(value, key)),
        do: {:cont, :ok},
        else: {:halt, {:error, {:invalid_field, key}}}
    end)
  end

  defp valid_optional_uuid?(nil), do: true
  defp valid_optional_uuid?(id) when is_binary(id), do: ClosedMap.uuid_string(id)
  defp valid_optional_uuid?(_), do: false

  defp optional_map(value, key) do
    case Map.get(value, key) do
      nil ->
        :ok

      item when is_map(item) ->
        if ClosedMap.json?(item), do: :ok, else: {:error, {:invalid_field, key}}

      _ ->
        {:error, {:invalid_field, key}}
    end
  end

  defp optional_strings(value, key) do
    case Map.get(value, key) do
      nil ->
        :ok

      list when is_list(list) ->
        if Enum.all?(list, &ClosedMap.nonempty_string/1),
          do: :ok,
          else: {:error, {:invalid_field, key}}

      _ ->
        {:error, {:invalid_field, key}}
    end
  end

  defp optional_json_list(value, key) do
    case Map.get(value, key) do
      nil ->
        :ok

      list when is_list(list) ->
        if ClosedMap.json?(list), do: :ok, else: {:error, {:invalid_field, key}}

      _ ->
        {:error, {:invalid_field, key}}
    end
  end

  defp optional_string(value, key) do
    case Map.get(value, key) do
      nil ->
        :ok

      item when is_binary(item) ->
        if String.trim(item) == "", do: {:error, {:invalid_field, key}}, else: :ok

      _ ->
        {:error, {:invalid_field, key}}
    end
  end

  defp optional_hash(value, key) do
    case Map.get(value, key) do
      nil ->
        :ok

      item when is_binary(item) ->
        if Regex.match?(~r/^[0-9a-f]{64}$/, item), do: :ok, else: {:error, {:invalid_field, key}}

      _ ->
        {:error, {:invalid_field, key}}
    end
  end

  defp stringify_keys(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
end
