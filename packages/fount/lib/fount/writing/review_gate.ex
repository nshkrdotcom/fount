defmodule Fount.Writing.ReviewGate do
  @moduledoc """
  Pure authorization-time validation for an exact stored candidate/review pair.

  PostgreSQL acceptance additionally locks and compares the accepted head. This
  gate never treats a missing, malformed, or unknown required check as passing.
  """

  alias Fount.Writing.{CheckSet, Principal, Review}

  @spec validate(map(), Review.t(), Principal.t()) :: :ok | {:error, term()}
  def validate(candidate, %Review{} = review, %Principal{} = approver) when is_map(candidate) do
    with :ok <- validate_identity(candidate, review),
         :ok <- validate_review(candidate, review, approver),
         :ok <-
           CheckSet.validate_stored(
             candidate,
             Map.get(candidate, "checks", []),
             Map.get(candidate, "report_ids", []),
             Map.get(candidate, "check_set_fingerprint", "")
           ) do
      validate_checks(candidate, review, approver)
    end
  end

  # The old actor/map review signature is intentionally not a writable path.
  def validate(_, _, _), do: {:error, :authorized_approval_required}

  defp validate_identity(candidate, review) do
    cond do
      review.base_revision_id != candidate["base_revision_id"] -> {:error, :candidate_base_mismatch}
      review.candidate_id != candidate["id"] -> {:error, :review_candidate_mismatch}
      review.content_hash != candidate["content_hash"] -> {:error, :review_content_mismatch}
      review.check_set_fingerprint != candidate["check_set_fingerprint"] -> {:error, :review_check_set_mismatch}
      MapSet.new(review.report_ids) != MapSet.new(Map.get(candidate, "report_ids", [])) -> {:error, :review_reports_mismatch}
      true -> :ok
    end
  end

  defp validate_review(candidate, review, approver) do
    cond do
      Map.get(candidate, "structural_errors", []) != [] -> {:error, :invalid_model}
      review.recommendation != :approve -> {:error, :review_rejected}
      review.reviewer != approver -> {:error, :review_approver_mismatch}
      approver.type in [:agent, :service] and review.overrides != [] -> {:error, :automated_override_forbidden}
      true -> :ok
    end
  end

  defp validate_checks(candidate, review, approver) do
    checks = Map.new(Map.get(candidate, "checks", []), &{&1["constraint_id"], &1})
    required = Map.get(candidate, "required_checks", [])
    overrides = Map.new(review.overrides, &{field(&1, :constraint_id), field(&1, :reason)})
    allowed_override_ids = MapSet.new(for definition <- required, definition["overridable"], do: definition["constraint_id"])

    cond do
      Enum.any?(Map.keys(overrides), &(not MapSet.member?(allowed_override_ids, &1))) ->
        {:error, :invalid_override_target}

      true ->
        blockers =
          Enum.flat_map(required, fn definition ->
            check = checks[definition["constraint_id"]]
            blocker(definition, check, overrides, approver)
          end)

        if blockers == [], do: :ok, else: {:error, {:review_blockers, blockers}}
    end
  end

  defp blocker(_definition, %{"status" => "pass"}, _overrides, _approver), do: []

  defp blocker(%{"evaluation" => "semantic", "overridable" => true, "constraint_id" => id}, check, overrides, %Principal{type: :human}) do
    case Map.get(overrides, id) do
      reason when is_binary(reason) and byte_size(String.trim(reason)) > 0 -> []
      _ -> [%{"constraint_id" => id, "reason" => "human_override_required", "status" => status(check)}]
    end
  end

  defp blocker(definition, check, _overrides, _approver) do
    [
      %{
        "constraint_id" => definition["constraint_id"],
        "reason" => "required_check_not_passing",
        "evaluation" => definition["evaluation"],
        "status" => status(check)
      }
    ]
  end

  defp status(nil), do: "missing"
  defp status(check), do: Map.get(check, "status", "unknown")
  defp field(map, key), do: Map.get(map, key, Map.get(map, to_string(key)))
end
