defmodule Fount.Intelligence.Evaluation.Annotation do
  @moduledoc """
  Stable semantic human annotations with independent-reader preservation.

  Human labels deliberately do not store provider encodings, logits or output-contract
  digests. Reader checkpoints additionally require first-exposure presentation position.
  """

  alias Fount.Writing.CanonicalJSON

  @kinds ~w(semantic_label reader_checkpoint writer_usefulness)
  @required ~w(annotation_id corpus_item_id unit_id annotator_id kind construct response)
  @optional ~w(confidence rationale checkpoint blinding created_at)
  @forbidden_fragments ~w(provider model logit token output_contract probability probabilities)

  @spec validate(map()) :: {:ok, map()} | {:error, atom()}
  def validate(annotation) when is_map(annotation) do
    with :ok <- keys(annotation),
         :ok <- strings(annotation),
         true <- annotation["kind"] in @kinds,
         :ok <- confidence(annotation["confidence"]),
         :ok <- response(annotation["response"]),
         :ok <- checkpoint(annotation),
         :ok <- no_provider_encoding(annotation),
         {:ok, _} <- CanonicalJSON.encode(annotation) do
      {:ok, Map.put(annotation, "annotation_sha256", CanonicalJSON.hash(annotation))}
    else
      _ -> {:error, :invalid_human_annotation}
    end
  rescue
    _ -> {:error, :invalid_human_annotation}
  end

  def validate(_), do: {:error, :invalid_human_annotation}

  @doc "Preserves every annotator response while adding a distribution only when semantic labels exist."
  @spec summarize([map()]) :: {:ok, map()} | {:error, atom()}
  def summarize(annotations) when is_list(annotations) and annotations != [] do
    with {:ok, validated} <- validate_many(annotations),
         true <- one_subject?(validated) do
      {:ok, summarize_validated(validated)}
    else
      _ -> {:error, :incompatible_human_annotations}
    end
  end

  def summarize(_), do: {:error, :invalid_human_annotations}

  defp summarize_validated(validated) do
    labels =
      validated
      |> Enum.map(&get_in(&1, ["response", "label"]))
      |> Enum.reject(&is_nil/1)

    counts = Enum.frequencies(labels)
    total = max(length(labels), 1)

    distribution =
      if labels == [],
        do: nil,
        else: Map.new(counts, fn {label, count} -> {label, count / total} end)

    %{
      "corpus_item_id" => hd(validated)["corpus_item_id"],
      "unit_id" => hd(validated)["unit_id"],
      "kind" => hd(validated)["kind"],
      "construct" => hd(validated)["construct"],
      "reader_count" => length(validated),
      "label_distribution" => distribution,
      "agreement" => agreement(counts, length(labels)),
      "mean_confidence" => mean_confidence(validated),
      "annotations" => validated
    }
  end

  @spec summarize_groups([map()]) :: {:ok, [map()]} | {:error, atom()}
  def summarize_groups(annotations) when is_list(annotations) do
    with {:ok, validated} <- validate_many(annotations) do
      validated
      |> Enum.group_by(&group_key/1)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reduce_while({:ok, []}, fn {_key, group}, {:ok, acc} ->
        {:cont, {:ok, acc ++ [summarize_validated(group)]}}
      end)
    end
  end

  def summarize_groups(_), do: {:error, :invalid_human_annotations}

  defp validate_many(annotations) do
    Enum.reduce_while(annotations, {:ok, []}, fn annotation, {:ok, acc} ->
      case validate(annotation) do
        {:ok, value} -> {:cont, {:ok, acc ++ [value]}}
        error -> {:halt, error}
      end
    end)
  end

  defp keys(annotation) do
    keys = Map.keys(annotation)
    allowed = @required ++ @optional
    if @required -- keys == [] and keys -- allowed == [], do: :ok, else: :error
  end

  defp strings(annotation) do
    required = ~w(annotation_id corpus_item_id unit_id annotator_id kind construct)
    optional = ~w(rationale created_at)

    if Enum.all?(required, &nonblank?(annotation[&1])) and
         Enum.all?(optional, fn key ->
           not Map.has_key?(annotation, key) or is_nil(annotation[key]) or
             nonblank?(annotation[key])
         end),
       do: :ok,
       else: :error
  end

  defp response(response) when is_map(response) do
    allowed = ~w(label ordinal value text selections)

    meaningful? =
      Enum.any?([
        nonblank?(response["label"]),
        is_integer(response["ordinal"]),
        is_number(response["value"]),
        nonblank?(response["text"]),
        is_list(response["selections"]) and response["selections"] != []
      ])

    if Map.keys(response) -- allowed == [] and meaningful? and
         valid_optional_label(response["label"]) and valid_selections(response["selections"]),
       do: :ok,
       else: :error
  end

  defp response(_), do: :error

  defp checkpoint(%{"kind" => "reader_checkpoint", "checkpoint" => checkpoint})
       when is_map(checkpoint) do
    allowed = ~w(presentation_index first_exposure prompt timestamp_ms)

    if Map.keys(checkpoint) -- allowed == [] and
         is_integer(checkpoint["presentation_index"]) and checkpoint["presentation_index"] >= 0 and
         checkpoint["first_exposure"] == true and nonblank?(checkpoint["prompt"]) and
         (is_nil(checkpoint["timestamp_ms"]) or
            (is_integer(checkpoint["timestamp_ms"]) and checkpoint["timestamp_ms"] >= 0)),
       do: :ok,
       else: :error
  end

  defp checkpoint(%{"kind" => kind, "checkpoint" => nil}) when kind != "reader_checkpoint",
    do: :ok

  defp checkpoint(%{"kind" => kind} = annotation) when kind != "reader_checkpoint" do
    if Map.has_key?(annotation, "checkpoint"), do: :error, else: :ok
  end

  defp checkpoint(_), do: :error

  defp no_provider_encoding(value) when is_map(value) do
    if Enum.all?(value, &provider_free_entry?/1), do: :ok, else: :error
  end

  defp no_provider_encoding(value) when is_list(value) do
    if Enum.all?(value, &(no_provider_encoding(&1) == :ok)), do: :ok, else: :error
  end

  defp no_provider_encoding(_), do: :ok

  defp provider_free_entry?({key, child}) do
    key = String.downcase(to_string(key))

    not Enum.any?(@forbidden_fragments, &String.contains?(key, &1)) and
      no_provider_encoding(child) == :ok
  end

  defp one_subject?(annotations),
    do: annotations |> Enum.map(&group_key/1) |> Enum.uniq() |> length() == 1

  defp group_key(a), do: {a["corpus_item_id"], a["unit_id"], a["kind"], a["construct"]}

  defp agreement(_counts, 0), do: nil
  defp agreement(counts, total), do: counts |> Map.values() |> Enum.max() |> Kernel./(total)

  defp mean_confidence(annotations) do
    values = annotations |> Enum.map(& &1["confidence"]) |> Enum.filter(&is_number/1)
    if values == [], do: nil, else: Enum.sum(values) / length(values)
  end

  defp confidence(nil), do: :ok
  defp confidence(value) when is_number(value) and value >= 0 and value <= 1, do: :ok
  defp confidence(_), do: :error

  defp valid_optional_label(nil), do: true
  defp valid_optional_label(value), do: nonblank?(value)
  defp valid_selections(nil), do: true

  defp valid_selections(values) when is_list(values) and values != [],
    do: Enum.all?(values, &nonblank?/1)

  defp valid_selections(_), do: false

  defp nonblank?(value),
    do: is_binary(value) and String.trim(value) != "" and String.valid?(value)
end
