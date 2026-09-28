defmodule Fount.Writing.Review do
  @moduledoc "Typed, canonically serializable review bound to one exact saved candidate."

  alias Fount.Screenplay.Model
  alias Fount.Writing.{CanonicalJSON, Principal}

  @enforce_keys [
    :reviewer,
    :candidate_id,
    :base_revision_id,
    :content_hash,
    :report_ids,
    :check_set_fingerprint,
    :recommendation
  ]
  defstruct [
    :reviewer,
    :candidate_id,
    :base_revision_id,
    :content_hash,
    :report_ids,
    :check_set_fingerprint,
    :recommendation,
    findings: [],
    overrides: []
  ]

  @type recommendation :: :approve | :reject
  @type t :: %__MODULE__{}

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    reviewer = Map.get(attrs, :reviewer) || Map.get(attrs, "reviewer")
    recommendation = normalize_recommendation(Map.get(attrs, :recommendation) || Map.get(attrs, "recommendation"))

    review = %__MODULE__{
      reviewer: reviewer,
      candidate_id: value(attrs, :candidate_id),
      base_revision_id: value(attrs, :base_revision_id),
      content_hash: value(attrs, :content_hash),
      report_ids: value(attrs, :report_ids) || [],
      check_set_fingerprint: value(attrs, :check_set_fingerprint),
      recommendation: recommendation,
      findings: value(attrs, :findings) || [],
      overrides: value(attrs, :overrides) || []
    }

    case validate(review) do
      :ok -> {:ok, review}
      {:error, _} = error -> error
    end
  end

  def new(_), do: {:error, :invalid_review}

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = review) do
    %{
      "reviewer" => Principal.to_map(review.reviewer),
      "candidate_id" => review.candidate_id,
      "base_revision_id" => review.base_revision_id,
      "content_hash" => review.content_hash,
      "report_ids" => review.report_ids,
      "check_set_fingerprint" => review.check_set_fingerprint,
      "findings" => Model.plain(review.findings),
      "recommendation" => Atom.to_string(review.recommendation),
      "overrides" => Model.plain(review.overrides)
    }
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(map) when is_map(map) do
    allowed = MapSet.new(~w(reviewer candidate_id base_revision_id content_hash report_ids check_set_fingerprint findings recommendation overrides))

    if MapSet.subset?(MapSet.new(Map.keys(map)), allowed) do
      with {:ok, reviewer} <- Principal.from_map(map["reviewer"] || %{}) do
        new(Map.put(map, "reviewer", reviewer))
      end
    else
      {:error, :unknown_review_field}
    end
  end

  def from_map(_), do: {:error, :invalid_review}

  @spec fingerprint(t()) :: String.t()
  def fingerprint(%__MODULE__{} = review), do: review |> to_map() |> CanonicalJSON.hash()

  defp validate(%__MODULE__{} = review) do
    cond do
      not match?(%Principal{}, review.reviewer) -> {:error, :invalid_reviewer}
      not nonblank?(review.candidate_id) -> {:error, :invalid_review_candidate}
      not nonblank?(review.base_revision_id) -> {:error, :invalid_review_base}
      not nonblank?(review.content_hash) -> {:error, :invalid_review_content_hash}
      not nonblank?(review.check_set_fingerprint) -> {:error, :invalid_check_set_fingerprint}
      review.recommendation not in [:approve, :reject] -> {:error, :invalid_review_recommendation}
      not string_list?(review.report_ids) or length(review.report_ids) != length(Enum.uniq(review.report_ids)) -> {:error, :invalid_review_reports}
      not is_list(review.findings) or not Enum.all?(review.findings, &is_map/1) -> {:error, :invalid_review_findings}
      not valid_overrides?(review.overrides) -> {:error, :invalid_overrides}
      true -> :ok
    end
  end

  defp valid_overrides?(overrides) when is_list(overrides) do
    Enum.all?(overrides, fn override ->
      is_map(override) and nonblank?(value(override, :constraint_id)) and nonblank?(value(override, :reason))
    end)
  end

  defp valid_overrides?(_), do: false
  defp string_list?(list), do: is_list(list) and Enum.all?(list, &nonblank?/1)
  defp nonblank?(value), do: is_binary(value) and String.trim(value) != ""
  defp value(map, key), do: Map.get(map, key, Map.get(map, to_string(key)))
  defp normalize_recommendation(value) when value in [:approve, :reject], do: value
  defp normalize_recommendation("approve"), do: :approve
  defp normalize_recommendation("reject"), do: :reject
  defp normalize_recommendation(_), do: nil
end
