defmodule FountRun.Decision do
  @moduledoc "Pure validation/fingerprinting for durable pending decisions."

  alias Fount.Writing.{CanonicalJSON, Principal}
  alias FountRun.ClosedMap

  @keys ~w(checkpoint_key kind prompt options step_id candidate_id base_revision_id content_hash check_set_fingerprint authorized_principal)
  @enforce_keys [:checkpoint_key, :kind, :prompt, :options, :authorized_principal, :context, :fingerprint]
  defstruct @enforce_keys ++ [:step_id, :candidate_id, :base_revision_id, :content_hash, :check_set_fingerprint]

  def new(attrs, %Principal{} = default_principal) do
    with {:ok, attrs} <- ClosedMap.normalize(attrs, @keys),
         {:ok, checkpoint} <- string(attrs, "checkpoint_key"),
         {:ok, kind} <- string(attrs, "kind"),
         {:ok, prompt} <- string(attrs, "prompt"),
         {:ok, options} <- options(Map.get(attrs, "options")),
         {:ok, principal} <- principal(Map.get(attrs, "authorized_principal"), default_principal),
         :ok <- optional_uuid(attrs, "step_id"),
         :ok <- optional_uuid(attrs, "candidate_id"),
         :ok <- optional_uuid(attrs, "base_revision_id"),
         :ok <- optional_hash(attrs, "content_hash"),
         :ok <- optional_hash(attrs, "check_set_fingerprint") do
      context = %{
        "checkpoint_key" => checkpoint,
        "kind" => kind,
        "prompt" => prompt,
        "options" => options,
        "step_id" => Map.get(attrs, "step_id"),
        "candidate_id" => Map.get(attrs, "candidate_id"),
        "base_revision_id" => Map.get(attrs, "base_revision_id"),
        "content_hash" => Map.get(attrs, "content_hash"),
        "check_set_fingerprint" => Map.get(attrs, "check_set_fingerprint"),
        "authorized_principal" => Principal.to_map(principal)
      }

      {:ok, struct!(__MODULE__, Map.merge(context, %{"authorized_principal" => principal, "context" => context, "fingerprint" => CanonicalJSON.hash(context)}) |> atomize_known())}
    end
  end

  defp atomize_known(map) do
    Enum.reduce(map, %{}, fn
      {"checkpoint_key", v}, a -> Map.put(a, :checkpoint_key, v)
      {"kind", v}, a -> Map.put(a, :kind, v)
      {"prompt", v}, a -> Map.put(a, :prompt, v)
      {"options", v}, a -> Map.put(a, :options, v)
      {"step_id", v}, a -> Map.put(a, :step_id, v)
      {"authorized_principal", v}, a -> Map.put(a, :authorized_principal, v)
      {"candidate_id", v}, a -> Map.put(a, :candidate_id, v)
      {"base_revision_id", v}, a -> Map.put(a, :base_revision_id, v)
      {"content_hash", v}, a -> Map.put(a, :content_hash, v)
      {"check_set_fingerprint", v}, a -> Map.put(a, :check_set_fingerprint, v)
      {"context", v}, a -> Map.put(a, :context, v)
      {"fingerprint", v}, a -> Map.put(a, :fingerprint, v)
    end)
  end

  defp string(attrs, key) do
    value = Map.get(attrs, key)
    if ClosedMap.nonempty_string(value), do: {:ok, value}, else: {:error, {:invalid_field, key}}
  end

  defp options(values) when is_list(values) and values != [] do
    if ClosedMap.json?(values), do: {:ok, values}, else: {:error, :invalid_decision_options}
  end
  defp options(_), do: {:error, :invalid_decision_options}

  defp principal(nil, %Principal{} = principal), do: {:ok, principal}
  defp principal(value, _default) do
    with {:ok, value} <- ClosedMap.normalize(value, ~w(type id)), do: Principal.from_map(value)
  end

  defp optional_uuid(attrs, key) do
    case Map.get(attrs, key) do
      nil -> :ok
      value -> if ClosedMap.uuid_string(value), do: :ok, else: {:error, {:invalid_field, key}}
    end
  end

  defp optional_hash(attrs, key) do
    case Map.get(attrs, key) do
      nil -> :ok
      value when is_binary(value) -> if Regex.match?(~r/^[0-9a-f]{64}$/, value), do: :ok, else: {:error, {:invalid_field, key}}
      _ -> {:error, {:invalid_field, key}}
    end
  end
end
