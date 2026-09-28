defmodule Fount.Writing.Approval do
  @moduledoc "Typed, stable approval identity and exact payload used by canonical acceptance."

  alias Fount.Writing.{CanonicalJSON, Principal, Review}

  @enforce_keys [
    :id,
    :approver,
    :screenplay_id,
    :candidate_id,
    :base_revision_id,
    :content_hash,
    :review
  ]
  defstruct [
    :id,
    :approver,
    :screenplay_id,
    :candidate_id,
    :base_revision_id,
    :content_hash,
    :review,
    :run_id,
    :run_policy_version,
    :run_policy_fingerprint
  ]

  @type t :: %__MODULE__{}

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    approval = %__MODULE__{
      id: value(attrs, :id),
      approver: Map.get(attrs, :approver) || Map.get(attrs, "approver"),
      screenplay_id: value(attrs, :screenplay_id),
      candidate_id: value(attrs, :candidate_id),
      base_revision_id: value(attrs, :base_revision_id),
      content_hash: value(attrs, :content_hash),
      review: Map.get(attrs, :review) || Map.get(attrs, "review"),
      run_id: value(attrs, :run_id),
      run_policy_version: value(attrs, :run_policy_version),
      run_policy_fingerprint: value(attrs, :run_policy_fingerprint)
    }

    case validate(approval) do
      :ok -> {:ok, approval}
      {:error, _} = error -> error
    end
  end

  def new(_), do: {:error, :invalid_approval}


  @doc "Builds a direct approval payload from an already loaded stored candidate; it does not create host authority."
  def direct(candidate, %Principal{} = principal, approval_id, opts \\ []) when is_map(candidate) do
    screenplay = value(candidate, :screenplay)
    provenance = value(candidate, :provenance) || %{}
    content_hash =
      case screenplay do
        %{revision: %{content_hash: hash}} -> hash
        _ -> value(candidate, :content_hash)
      end

    with {:ok, review} <-
           Review.new(
             reviewer: principal,
             candidate_id: value(candidate, :id),
             base_revision_id: value(candidate, :base_revision_id),
             content_hash: content_hash,
             report_ids: Map.get(provenance, "report_ids", []),
             check_set_fingerprint: value(candidate, :check_set_fingerprint),
             findings: Keyword.get(opts, :findings, []),
             recommendation: Keyword.get(opts, :recommendation, :approve),
             overrides: Keyword.get(opts, :overrides, [])
           ) do
      new(
        id: approval_id,
        approver: principal,
        screenplay_id: value(candidate, :screenplay_id) || (screenplay && screenplay.id),
        candidate_id: value(candidate, :id),
        base_revision_id: value(candidate, :base_revision_id),
        content_hash: content_hash,
        review: review,
        run_id: Keyword.get(opts, :run_id),
        run_policy_version: Keyword.get(opts, :run_policy_version),
        run_policy_fingerprint: Keyword.get(opts, :run_policy_fingerprint)
      )
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = approval) do
    %{
      "approval_id" => approval.id,
      "approver" => Principal.to_map(approval.approver),
      "screenplay_id" => approval.screenplay_id,
      "candidate_id" => approval.candidate_id,
      "base_revision_id" => approval.base_revision_id,
      "content_hash" => approval.content_hash,
      "review" => Review.to_map(approval.review),
      "run_id" => approval.run_id,
      "run_policy_version" => approval.run_policy_version,
      "run_policy_fingerprint" => approval.run_policy_fingerprint
    }
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(map) when is_map(map) do
    allowed = MapSet.new(~w(approval_id approver screenplay_id candidate_id base_revision_id content_hash review run_id run_policy_version run_policy_fingerprint))

    if MapSet.subset?(MapSet.new(Map.keys(map)), allowed) do
      with {:ok, approver} <- Principal.from_map(map["approver"] || %{}),
           {:ok, review} <- Review.from_map(map["review"] || %{}) do
        new(%{
          id: map["approval_id"],
          approver: approver,
          screenplay_id: map["screenplay_id"],
          candidate_id: map["candidate_id"],
          base_revision_id: map["base_revision_id"],
          content_hash: map["content_hash"],
          review: review,
          run_id: map["run_id"],
          run_policy_version: map["run_policy_version"],
          run_policy_fingerprint: map["run_policy_fingerprint"]
        })
      end
    else
      {:error, :unknown_approval_field}
    end
  end

  def from_map(_), do: {:error, :invalid_approval}

  @spec fingerprint(t()) :: String.t()
  def fingerprint(%__MODULE__{} = approval), do: approval |> to_map() |> CanonicalJSON.hash()

  defp validate(%__MODULE__{} = approval) do
    run_values = [approval.run_id, approval.run_policy_version, approval.run_policy_fingerprint]

    cond do
      Ecto.UUID.cast(approval.id) == :error -> {:error, :invalid_approval_id}
      not match?(%Principal{}, approval.approver) -> {:error, :invalid_approver}
      not nonblank?(approval.screenplay_id) -> {:error, :invalid_approval_screenplay}
      not nonblank?(approval.candidate_id) -> {:error, :invalid_approval_candidate}
      not nonblank?(approval.base_revision_id) -> {:error, :invalid_approval_base}
      not nonblank?(approval.content_hash) -> {:error, :invalid_approval_content_hash}
      not match?(%Review{}, approval.review) -> {:error, :invalid_approval_review}
      Enum.all?(run_values, &is_nil/1) -> :ok
      Enum.any?(run_values, &is_nil/1) -> {:error, :incomplete_run_provenance}
      not nonblank?(approval.run_id) or not is_integer(approval.run_policy_version) or approval.run_policy_version < 1 or not nonblank?(approval.run_policy_fingerprint) -> {:error, :invalid_run_provenance}
      true -> :ok
    end
  end

  defp nonblank?(value), do: is_binary(value) and String.trim(value) != ""
  defp value(map, key), do: Map.get(map, key, Map.get(map, to_string(key)))
end
