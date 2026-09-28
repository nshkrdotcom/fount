defmodule Fount.Intelligence.Evaluation.CorpusManifest do
  @moduledoc """
  Rights/provenance policy for evaluation material.

  Validation is fail-closed. Public availability never implies storage, human-review,
  hosted-provider, local-model or redistribution permission. Hosted Observe and hosted
  Inference are distinct permissions, and no credential-like keys are accepted.
  """

  alias Fount.Writing.CanonicalJSON

  @permission_keys ~w(local_storage human_review observe_hosted inference_hosted local_model redistribution)
  @required ~w(corpus_item_id label rights_basis rights_evidence_ref allowed_uses provider_export_allowed human_review_allowed redistribution_allowed retention_policy confidentiality_class permissions)
  @optional ~w(source_sha256 created_at ingested_at notes study_id)
  @secret_fragments ~w(api_key authorization bearer credential credentials password secret token)

  @type use_kind ::
          :local_storage
          | :human_review
          | :observe_hosted
          | :inference_hosted
          | :local_model
          | :redistribution

  @spec validate(map()) :: {:ok, map()} | {:error, atom()}
  def validate(manifest) when is_map(manifest) do
    with :ok <- exact_keys(manifest),
         :ok <- required_strings(manifest),
         :ok <- string_list(manifest["allowed_uses"]),
         :ok <- booleans(manifest),
         :ok <- permissions(manifest),
         :ok <- aggregate_permissions(manifest),
         :ok <- digest(manifest["source_sha256"]),
         :ok <- no_secret_keys(manifest),
         {:ok, _} <- CanonicalJSON.encode(manifest) do
      {:ok, Map.put(manifest, "manifest_sha256", CanonicalJSON.hash(manifest))}
    else
      _ -> {:error, :invalid_corpus_manifest}
    end
  rescue
    _ -> {:error, :invalid_corpus_manifest}
  end

  def validate(_), do: {:error, :invalid_corpus_manifest}

  @spec authorize(map(), use_kind()) :: :ok | {:error, atom()}
  def authorize(manifest, use_kind)
      when use_kind in ~w(local_storage human_review observe_hosted inference_hosted local_model redistribution)a do
    with {:ok, validated} <- validate(manifest),
         true <- permitted?(validated, use_kind) do
      :ok
    else
      {:error, _} = error -> error
      false -> {:error, :corpus_use_not_permitted}
    end
  end

  def authorize(_manifest, _use_kind), do: {:error, :invalid_corpus_use}

  @spec summary(map()) :: {:ok, map()} | {:error, atom()}
  def summary(manifest) do
    with {:ok, validated} <- validate(manifest) do
      {:ok,
       %{
         "corpus_item_id" => validated["corpus_item_id"],
         "label" => validated["label"],
         "rights_basis" => validated["rights_basis"],
         "allowed_uses" => validated["allowed_uses"],
         "permissions" => validated["permissions"],
         "retention_policy" => validated["retention_policy"],
         "confidentiality_class" => validated["confidentiality_class"],
         "manifest_sha256" => validated["manifest_sha256"]
       }}
    end
  end

  defp permitted?(manifest, use_kind) do
    key = Atom.to_string(use_kind)
    permission = manifest["permissions"][key] == true
    permission and upper_bound?(manifest, use_kind)
  end

  defp upper_bound?(manifest, kind) when kind in [:observe_hosted, :inference_hosted],
    do: manifest["provider_export_allowed"] == true

  defp upper_bound?(manifest, :human_review), do: manifest["human_review_allowed"] == true
  defp upper_bound?(manifest, :redistribution), do: manifest["redistribution_allowed"] == true
  defp upper_bound?(_manifest, _kind), do: true

  defp exact_keys(manifest) do
    keys = Map.keys(manifest)
    allowed = @required ++ @optional

    if @required -- keys == [] and keys -- allowed == [], do: :ok, else: :error
  end

  defp required_strings(manifest) do
    keys =
      ~w(corpus_item_id label rights_basis rights_evidence_ref retention_policy confidentiality_class)

    if Enum.all?(keys, &nonblank?(manifest[&1])) and
         Enum.all?(@optional -- ["source_sha256"], fn key ->
           not Map.has_key?(manifest, key) or is_nil(manifest[key]) or nonblank?(manifest[key])
         end),
       do: :ok,
       else: :error
  end

  defp string_list(values) when is_list(values) and values != [] do
    if Enum.all?(values, &nonblank?/1) and length(values) == length(Enum.uniq(values)),
      do: :ok,
      else: :error
  end

  defp string_list(_), do: :error

  defp booleans(manifest) do
    if Enum.all?(
         ~w(provider_export_allowed human_review_allowed redistribution_allowed),
         &is_boolean(manifest[&1])
       ),
       do: :ok,
       else: :error
  end

  defp permissions(%{"permissions" => permissions}) when is_map(permissions) do
    if Enum.sort(Map.keys(permissions)) == Enum.sort(@permission_keys) and
         Enum.all?(Map.values(permissions), &is_boolean/1),
       do: :ok,
       else: :error
  end

  defp permissions(_), do: :error

  defp aggregate_permissions(manifest) do
    p = manifest["permissions"]

    valid =
      (manifest["provider_export_allowed"] or
         (not p["observe_hosted"] and not p["inference_hosted"])) and
        (manifest["human_review_allowed"] or not p["human_review"]) and
        (manifest["redistribution_allowed"] or not p["redistribution"])

    if valid, do: :ok, else: :error
  end

  defp digest(nil), do: :ok

  defp digest(value) when is_binary(value) do
    if Regex.match?(~r/^[0-9a-f]{64}$/, value), do: :ok, else: :error
  end

  defp digest(_), do: :error

  defp no_secret_keys(value) when is_map(value) do
    if Enum.all?(value, &safe_entry?/1), do: :ok, else: :error
  end

  defp no_secret_keys(value) when is_list(value) do
    if Enum.all?(value, &(no_secret_keys(&1) == :ok)), do: :ok, else: :error
  end

  defp no_secret_keys(_), do: :ok

  defp safe_entry?({key, child}) do
    key = String.downcase(to_string(key))

    not Enum.any?(@secret_fragments, &String.contains?(key, &1)) and
      no_secret_keys(child) == :ok
  end

  defp nonblank?(value),
    do: is_binary(value) and String.trim(value) != "" and String.valid?(value)
end
