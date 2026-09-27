defmodule Fount.Intelligence.Packs.GenrePack do
  @moduledoc "Validation and composition for data-only Phase-8 genre/craft packs."

  alias Fount.Intelligence.Capabilities
  alias Fount.Intelligence.Playbooks.WriterRegistry
  alias Fount.Observe.{DeclarativeLens, Registry}
  alias Fount.Writing.CanonicalJSON

  @allowed ~w(id description purpose trust source lenses capability_families playbooks diagnostic_salience writer_intent_prompts intent resource_policy_request)
  @trust ~w(core studio project third_party)
  @intent_keys ~w(subversions opt_out)
  @resource_keys ~w(max_targets max_states max_provider_requests max_wall_ms)
  @default_host_caps %{
    "max_targets" => 500,
    "max_states" => 500,
    "max_provider_requests" => 500,
    "max_wall_ms" => 120_000
  }

  @forbidden ~w(module function mfa command shell path file endpoint base_url url credentials credential api_key token headers http database query callback decoder adapter tool)

  def validate(asset, opts \\ [])

  def validate(asset, opts) when is_map(asset) do
    custom_lenses = Keyword.get(opts, :custom_lenses, %{})
    host_caps = Keyword.get(opts, :host_caps, @default_host_caps)

    with :ok <- exact_keys(asset),
         true <- asset["trust"] in @trust,
         :ok <- source(asset["source"]),
         :ok <- string_list(asset["lenses"]),
         :ok <- string_list(asset["capability_families"]),
         :ok <- string_list(asset["playbooks"]),
         :ok <- registered_lenses(asset["lenses"], custom_lenses),
         true <- Enum.all?(asset["capability_families"], &Capabilities.member?/1),
         true <- Enum.all?(asset["playbooks"], &WriterRegistry.member?/1),
         :ok <- salience(asset["diagnostic_salience"]),
         :ok <- string_list(asset["writer_intent_prompts"]),
         :ok <- intent(asset["intent"]),
         {:ok, effective_policy} <- resource_policy(asset["resource_policy_request"], host_caps),
         {:ok, bytes} <- CanonicalJSON.encode(asset),
         true <- byte_size(bytes) <= 65_536 do
      normalized = Map.put(asset, "effective_resource_policy", effective_policy)
      {:ok, Map.put(normalized, "sha256", CanonicalJSON.hash(asset))}
    else
      _ -> {:error, :invalid_genre_pack}
    end
  rescue
    _ -> {:error, :invalid_genre_pack}
  end

  def validate(_, _), do: {:error, :invalid_genre_pack}

  def preview(asset, opts \\ []) do
    with {:ok, value} <- validate(asset, opts) do
      {:ok,
       %{
         "id" => value["id"],
         "sha256" => value["sha256"],
         "trust" => value["trust"],
         "source" => value["source"],
         "purpose" => value["purpose"],
         "composition" => %{
           "lenses" => value["lenses"],
           "capability_families" => value["capability_families"],
           "playbooks" => value["playbooks"]
         },
         "diagnostic_salience" => value["diagnostic_salience"],
         "intent" => value["intent"],
         "effective_resource_policy" => value["effective_resource_policy"],
         "enabled" => false
       }}
    end
  end

  def host_caps, do: @default_host_caps

  defp exact_keys(asset) do
    required =
      ~w(id description purpose trust source lenses capability_families playbooks diagnostic_salience writer_intent_prompts intent resource_policy_request)

    if Map.keys(asset) -- @allowed == [] and Enum.all?(required, &Map.has_key?(asset, &1)) and
         valid_text(asset["id"]) and valid_text(asset["description"]) and
         valid_text(asset["purpose"]) and
         no_forbidden_nested_keys?(asset),
       do: :ok,
       else: {:error, :invalid_keys}
  end

  defp registered_lenses(ids, custom) when is_map(custom) do
    valid =
      Enum.all?(ids, &(Registry.lens?(&1) or DeclarativeLens.installed_enabled?(custom, &1)))

    if valid, do: :ok, else: {:error, :unknown_lens}
  end

  defp source(%{"label" => label} = value) when is_binary(label) and label != "" do
    if Map.keys(value) -- ~w(label revision owner) == [] and
         Enum.all?(Map.values(value), &(is_nil(&1) or is_binary(&1))),
       do: :ok,
       else: {:error, :invalid_source}
  end

  defp source(_), do: {:error, :invalid_source}

  defp salience(value) when is_map(value) do
    if Enum.all?(value, fn {key, weight} ->
         valid_text(key) and is_number(weight) and weight >= 0 and weight <= 1
       end),
       do: :ok,
       else: {:error, :invalid_salience}
  end

  defp salience(_), do: {:error, :invalid_salience}

  defp intent(value) when is_map(value) do
    if Map.keys(value) -- @intent_keys == [] and
         Enum.all?(@intent_keys, fn key -> string_list(Map.get(value, key, [])) == :ok end),
       do: :ok,
       else: {:error, :invalid_intent}
  end

  defp intent(_), do: {:error, :invalid_intent}

  defp resource_policy(requested, host_caps) when is_map(requested) and is_map(host_caps) do
    valid =
      Map.keys(requested) -- @resource_keys == [] and Map.keys(host_caps) -- @resource_keys == [] and
        Enum.all?(requested, fn {_, value} -> is_integer(value) and value > 0 end) and
        Enum.all?(host_caps, fn {_, value} -> is_integer(value) and value > 0 end) and
        Enum.all?(requested, fn {key, value} -> value <= Map.get(host_caps, key, 0) end)

    if valid,
      do:
        {:ok,
         Map.new(
           @resource_keys,
           &{&1,
            min(Map.get(requested, &1, Map.fetch!(host_caps, &1)), Map.fetch!(host_caps, &1))}
         )},
      else: {:error, :resource_policy_exceeds_host}
  end

  defp resource_policy(_, _), do: {:error, :invalid_resource_policy}

  defp string_list(value) when is_list(value) do
    if Enum.all?(value, &valid_text/1) and length(value) == length(Enum.uniq(value)),
      do: :ok,
      else: {:error, :invalid_string_list}
  end

  defp string_list(_), do: {:error, :invalid_string_list}

  defp valid_text(value), do: is_binary(value) and String.trim(value) != ""

  defp no_forbidden_nested_keys?(value) when is_map(value) do
    Enum.all?(value, fn {key, nested} ->
      String.downcase(to_string(key)) not in @forbidden and no_forbidden_nested_keys?(nested)
    end)
  end

  defp no_forbidden_nested_keys?(items) when is_list(items),
    do: Enum.all?(items, &no_forbidden_nested_keys?/1)

  defp no_forbidden_nested_keys?(_), do: true
end
