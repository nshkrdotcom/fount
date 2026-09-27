defmodule Fount.Observe.Calibration do
  @moduledoc """
  Data-only post-measurement transforms. Raw probabilities and provider confidence
  remain untouched. Experimental temperature transforms are not empirical reader
  calibration; validated assets require a declared model and corpus digest.
  """
  import Kernel, except: [apply: 3]
  alias Fount.Observe.{Distribution, Error, OutputContract}
  alias Fount.Writing.CanonicalJSON

  def load("identity") do
    with {:ok, bytes} <-
           File.read(Application.app_dir(:fount_observe, "priv/calibrations/identity.json")),
         {:ok, asset} <- Jason.decode(bytes),
         do: validate(asset)
  end

  def load(_), do: unavailable()

  def validate(nil), do: {:ok, nil}

  def validate(asset) when is_map(asset) do
    raw = Map.delete(asset, "sha256")
    allowed = ~w(id method temperature validation model corpus_sha256 description)

    valid =
      Map.keys(raw) -- allowed == [] and OutputContract.logical_id?(raw["id"]) and
        valid_method?(raw) and valid_claim?(raw) and
        (not Map.has_key?(raw, "model") or (is_binary(raw["model"]) and raw["model"] != ""))

    with true <- valid,
         {:ok, bytes} <- CanonicalJSON.encode(raw),
         true <- byte_size(bytes) <= 16_384 do
      sha = CanonicalJSON.hash(raw)

      if Map.has_key?(asset, "sha256") and asset["sha256"] != sha,
        do: unavailable(),
        else: {:ok, Map.put(raw, "sha256", sha)}
    else
      _ -> unavailable()
    end
  rescue
    _ -> unavailable()
  end

  def validate(_), do: unavailable()

  def apply(_distribution, nil, _fingerprint), do: {:ok, nil}

  def apply(%Distribution{} = distribution, asset, fingerprint) do
    with {:ok, asset} <- validate(asset),
         :ok <- Distribution.validate(distribution),
         true <- model_matches?(asset, fingerprint) do
      temperature = Map.get(asset, "temperature", 1.0)
      # Normalize only the derived view. The original provider values remain intact.
      powers =
        Enum.map(distribution.values, fn {k, p} -> {k, :math.pow(p, 1.0 / temperature)} end)

      total = Enum.sum(Enum.map(powers, &elem(&1, 1)))
      probabilities = Enum.map(powers, fn {k, p} -> {k, p / total} end)

      {:ok,
       %{
         "asset_sha256" => asset["sha256"],
         "id" => asset["id"],
         "validation" => asset["validation"],
         "validation_basis" => "asset_author_declaration_not_verified_by_runtime",
         "probabilities" => Map.new(probabilities),
         "diagnostics" => diagnostics(probabilities),
         "confidence_calibrated" => false
       }}
    else
      _ -> unavailable()
    end
  rescue
    _ -> unavailable()
  end

  def apply(_, _, _), do: unavailable()

  def diagnostics(values) when is_list(values) do
    weights = Enum.map(values, &elem(&1, 1))
    total = Enum.sum(weights)
    normalized = Enum.map(weights, &(&1 / total))
    [first, second | _] = Enum.sort(normalized, :desc)

    entropy =
      -Enum.sum(Enum.map(normalized, fn p -> if p > 0, do: p * :math.log(p), else: 0.0 end))

    %{
      "top_probability" => first,
      "margin" => first - second,
      "entropy_nats" => entropy,
      "probability_sum" => total
    }
  end

  defp valid_method?(%{"method" => "identity"} = a), do: not Map.has_key?(a, "temperature")

  defp valid_method?(%{"method" => "temperature", "temperature" => t}),
    do: is_number(t) and t >= 0.05 and t <= 20

  defp valid_method?(_), do: false
  defp valid_claim?(%{"method" => "identity", "validation" => "identity_not_empirical"}), do: true
  defp valid_claim?(%{"validation" => "experimental"}), do: true

  defp valid_claim?(%{"validation" => "empirical", "model" => model, "corpus_sha256" => sha}),
    do: is_binary(model) and is_binary(sha) and Regex.match?(~r/^[0-9a-f]{64}$/, sha)

  defp valid_claim?(_), do: false

  defp model_matches?(asset, fp),
    do:
      not Map.has_key?(asset, "model") or
        asset["model"] == Map.get(fp, "reported_model", fp["model"])

  defp unavailable, do: {:error, Error.new(:calibration_unavailable)}
end
