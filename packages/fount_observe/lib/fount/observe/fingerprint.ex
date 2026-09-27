defmodule Fount.Observe.Fingerprint do
  @moduledoc false
  alias Fount.Observe.{Error, Provider}
  alias Fount.Writing.CanonicalJSON

  @allowed ~w(provider endpoint_kind endpoint_sha256 model reported_model stability session fixture_sha256 fixtures_sha256 sdk_version)

  def request(provider, request, opts, run_id) do
    with fp when is_map(fp) <- Provider.identity(provider, request),
         true <- Map.keys(fp) -- @allowed == [] and valid_fields?(fp),
         {:ok, _} <- CanonicalJSON.encode(fp) do
      # An override is not covered by a provider's identity claim for a different model.
      fp =
        if opts[:model] && opts[:model] != fp["model"],
          do:
            fp
            |> Map.put("model", opts[:model])
            |> Map.put("stability", "mutable_alias_or_unknown"),
          else: fp

      fp = if stable?(fp), do: fp, else: Map.put_new(fp, "session", run_id)

      if opts[:cache_policy] == :durable and not stable?(fp),
        do: {:error, Error.new(:unstable_model_identity_for_durable_cache)},
        else: {:ok, fp}
    else
      _ -> {:error, Error.new(:invalid_request)}
    end
  rescue
    _ -> {:error, Error.new(:invalid_request)}
  end

  defp valid_fields?(fp) do
    Enum.all?(["provider", "model"], fn key ->
      is_binary(fp[key]) and String.valid?(fp[key]) and fp[key] != ""
    end) and
      fp["stability"] in ~w(immutable_exact provider_stable mutable_alias_or_unknown)
  end

  def stable?(fp), do: fp["stability"] in ~w(immutable_exact provider_stable)

  def result(fp, metadata) do
    case metadata["model"] do
      model when is_binary(model) and byte_size(model) <= 256 ->
        Map.put(fp, "reported_model", model)

      _ ->
        fp
    end
  end

  def matches?(actual, requested),
    do: Map.delete(actual, "reported_model") == Map.delete(requested, "reported_model")
end
