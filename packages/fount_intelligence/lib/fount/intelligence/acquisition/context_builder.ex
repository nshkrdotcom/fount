defmodule Fount.Intelligence.Acquisition.ContextBuilder do
  @moduledoc "Shell-only conversion from plain Intelligence state into Observe-owned neutral context values."

  alias Fount.Intelligence.Diagnosis.Concern
  alias Fount.Observe.{Context, Error, Lens}
  alias Fount.Writing.CanonicalJSON

  @allowed_state_keys ~w(known_facts speaker_beliefs relationship_state)

  @spec build(String.t(), Concern.t() | map(), map(), [map()]) ::
          {:ok, Context.t()} | {:error, term()}
  def build(lens_id, concern, state \\ %{}, base_assessments \\ []) do
    with true <- is_binary(lens_id) and lens_id != "",
         {:ok, asset} <- Lens.load(lens_id),
         {:ok, concern_map} <- concern_map(concern),
         {:ok, state} <- normalize_state(state),
         true <- is_list(base_assessments),
         :ok <- plain_only?(base_assessments),
         {:ok, _} <- CanonicalJSON.encode(base_assessments) do
      slots =
        state
        |> Map.take(@allowed_state_keys)
        |> Map.put("concern", concern_map)
        |> maybe_put("base_assessments", base_assessments)

      Context.from_map(%{"slots" => slots}, asset["context_contract"])
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, _} = error -> error
      _ -> {:error, Error.at(:invalid_context, ["slots"])}
    end
  rescue
    _ -> {:error, Error.at(:invalid_context, ["slots"])}
  end

  @doc "Validates caller-supplied slots against an installed lens before any provider call."
  def validate(lens_id, slots) when is_binary(lens_id) and is_map(slots) do
    with {:ok, asset} <- Lens.load(lens_id),
         :ok <- plain_only?(slots),
         {:ok, _} <- CanonicalJSON.encode(slots) do
      Context.from_map(%{"slots" => stringify(slots)}, asset["context_contract"])
    else
      {:error, _} = error -> error
      _ -> {:error, Error.at(:invalid_context, ["slots"])}
    end
  rescue
    _ -> {:error, Error.at(:invalid_context, ["slots"])}
  end

  def validate(_, _), do: {:error, Error.at(:invalid_context, ["slots"])}

  defp concern_map(%Concern{} = concern), do: {:ok, Concern.to_map(concern)}

  defp concern_map(value) when is_map(value) do
    case Concern.new(value) do
      {:ok, concern} -> {:ok, Concern.to_map(concern)}
      error -> error
    end
  end

  defp concern_map(value) when is_binary(value), do: value |> Concern.new() |> then(fn
    {:ok, concern} -> {:ok, Concern.to_map(concern)}
    error -> error
  end)

  defp concern_map(_), do: {:error, :invalid_concern}

  defp normalize_state(state) when is_map(state) do
    state = stringify(state)

    if Map.keys(state) -- @allowed_state_keys == [] and plain_only?(state) == :ok,
      do: {:ok, state},
      else: {:error, :invalid_context_state}
  end

  defp normalize_state(_), do: {:error, :invalid_context_state}

  defp plain_only?(%{__struct__: module}) do
    if String.starts_with?(Atom.to_string(module), "Elixir.Fount.Intelligence."),
      do: {:error, :intelligence_struct_not_allowed},
      else: {:error, :struct_not_allowed}
  end

  defp plain_only?(map) when is_map(map) do
    if Map.has_key?(map, "__struct__") or Map.has_key?(map, :__struct__) do
      {:error, :struct_not_allowed}
    else
      Enum.reduce_while(map, :ok, fn {key, value}, :ok ->
        if (is_binary(key) or is_atom(key)) and plain_only?(value) == :ok,
          do: {:cont, :ok},
          else: {:halt, {:error, :non_plain_context_value}}
      end)
    end
  end

  defp plain_only?(list) when is_list(list) do
    if Enum.all?(list, &(plain_only?(&1) == :ok)), do: :ok, else: {:error, :non_plain_context_value}
  end

  defp plain_only?(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
       do: :ok

  defp plain_only?(_), do: {:error, :non_plain_context_value}

  defp stringify(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), stringify_value(value)}
      {key, value} -> {key, stringify_value(value)}
    end)
  end

  defp stringify_value(value) when is_map(value), do: stringify(value)
  defp stringify_value(value) when is_list(value), do: Enum.map(value, &stringify_value/1)
  defp stringify_value(value), do: value

  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
