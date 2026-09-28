defmodule FountRun.Plan do
  @moduledoc "Immutable, closed-schema work-plan snapshots."

  alias Fount.Writing.{CanonicalJSON, Principal}
  alias FountRun.ClosedMap

  @keys ~w(screenplay_id base_revision_id goal scope constraints protected_material input_brief input_notes operation_parameters)
  @input_keys ~w(reference sha256)
  @notes_keys ~w(reference sha256)
  @operation_keys ~w(workflow request_fingerprint selection_fingerprint)

  @enforce_keys [:screenplay_id, :base_revision_id, :goal, :scope, :constraints, :protected_material, :input_brief, :input_notes, :operation_parameters, :fingerprint, :author]
  defstruct @enforce_keys

  @type t :: %__MODULE__{}

  @spec new(map(), Principal.t()) :: {:ok, t()} | {:error, term()}
  def new(attrs, %Principal{} = author) do
    with {:ok, attrs} <- ClosedMap.normalize(attrs, @keys),
         {:ok, screenplay_id} <- required_uuid(attrs, "screenplay_id"),
         {:ok, base_revision_id} <- required_uuid(attrs, "base_revision_id"),
         {:ok, goal} <- required_string(attrs, "goal"),
         {:ok, scope} <- json_object(Map.get(attrs, "scope"), :invalid_scope),
         {:ok, constraints} <- json_list(Map.get(attrs, "constraints", []), :invalid_constraints),
         {:ok, protected} <- json_list(Map.get(attrs, "protected_material", []), :invalid_protected_material),
         {:ok, input_brief} <- input_ref(Map.get(attrs, "input_brief")),
         {:ok, input_notes} <- note_refs(Map.get(attrs, "input_notes", [])),
         {:ok, operation} <- operation(Map.get(attrs, "operation_parameters", %{})) do
      canonical = %{
        "screenplay_id" => screenplay_id,
        "base_revision_id" => base_revision_id,
        "goal" => goal,
        "scope" => scope,
        "constraints" => constraints,
        "protected_material" => protected,
        "input_brief" => input_brief,
        "input_notes" => input_notes,
        "operation_parameters" => operation
      }

      {:ok,
       struct!(__MODULE__,
         screenplay_id: screenplay_id,
         base_revision_id: base_revision_id,
         goal: goal,
         scope: scope,
         constraints: constraints,
         protected_material: protected,
         input_brief: input_brief,
         input_notes: input_notes,
         operation_parameters: operation,
         fingerprint: CanonicalJSON.hash(canonical),
         author: author
       )}
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = plan) do
    %{
      "screenplay_id" => plan.screenplay_id,
      "base_revision_id" => plan.base_revision_id,
      "goal" => plan.goal,
      "scope" => plan.scope,
      "constraints" => plan.constraints,
      "protected_material" => plan.protected_material,
      "input_brief" => plan.input_brief,
      "input_notes" => plan.input_notes,
      "operation_parameters" => plan.operation_parameters
    }
  end

  def same_base_and_scope?(%__MODULE__{} = left, %__MODULE__{} = right),
    do: left.base_revision_id == right.base_revision_id and left.scope == right.scope

  defp required_string(attrs, key) do
    value = Map.get(attrs, key)
    if ClosedMap.nonempty_string(value), do: {:ok, value}, else: {:error, {:invalid_field, key}}
  end

  defp required_uuid(attrs, key) do
    value = Map.get(attrs, key)
    if ClosedMap.uuid_string(value), do: {:ok, value}, else: {:error, {:invalid_field, key}}
  end

  defp json_object(value, error) when is_map(value), do: if(ClosedMap.json?(value), do: {:ok, value}, else: {:error, error})
  defp json_object(_, error), do: {:error, error}
  defp json_list(value, error) when is_list(value), do: if(ClosedMap.json?(value), do: {:ok, value}, else: {:error, error})
  defp json_list(_, error), do: {:error, error}

  defp input_ref(nil), do: {:ok, nil}
  defp input_ref(value) do
    with {:ok, value} <- ClosedMap.normalize(value, @input_keys),
         true <- ClosedMap.nonempty_string(Map.get(value, "reference")),
         true <- valid_hash?(Map.get(value, "sha256")) do
      {:ok, value}
    else
      false -> {:error, :invalid_input_brief}
      {:error, _} = error -> error
    end
  end

  defp note_refs(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      with {:ok, value} <- ClosedMap.normalize(value, @notes_keys),
           true <- ClosedMap.nonempty_string(Map.get(value, "reference")),
           true <- valid_hash?(Map.get(value, "sha256")) do
        {:cont, {:ok, [value | acc]}}
      else
        false -> {:halt, {:error, :invalid_input_notes}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end
  defp note_refs(_), do: {:error, :invalid_input_notes}

  # Phase 02 supports only durable generic operation identity. Phase 04 expands
  # this through the operation-specific Workshop validators before execution.
  defp operation(value) do
    with {:ok, value} <- ClosedMap.normalize(value, @operation_keys),
         :ok <- optional_string(value, "workflow"),
         :ok <- optional_hash(value, "request_fingerprint"),
         :ok <- optional_hash(value, "selection_fingerprint") do
      {:ok, value}
    end
  end

  defp optional_string(map, key) do
    case Map.get(map, key) do
      nil -> :ok
      value -> if ClosedMap.nonempty_string(value), do: :ok, else: {:error, {:invalid_field, key}}
    end
  end

  defp optional_hash(map, key) do
    case Map.get(map, key) do
      nil -> :ok
      value -> if valid_hash?(value), do: :ok, else: {:error, {:invalid_field, key}}
    end
  end

  defp valid_hash?(value), do: is_binary(value) and Regex.match?(~r/^[0-9a-f]{64}$/, value)
end
