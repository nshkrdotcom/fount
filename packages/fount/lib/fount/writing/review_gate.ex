defmodule Fount.Writing.ReviewGate do
  @moduledoc """
  Pure review validation before a PostgreSQL acceptance transaction.

  The transaction must additionally lock and compare the actual accepted head.
  This gate does not advance a draft or treat a missing external check as passed.
  """

  @spec validate(map(), map(), String.t()) :: :ok | {:error, term()}
  def validate(candidate, review, expected_revision)
      when is_map(candidate) and is_map(review) and is_binary(expected_revision) do
    with :ok <- validate_identity(candidate, review, expected_revision),
         :ok <- validate_review(candidate, review) do
      validate_checks(Map.get(candidate, "checks", []), Map.get(review, "overrides", []))
    end
  end

  def validate(_, _, _), do: {:error, :missing_review}

  defp validate_identity(candidate, review, expected_revision) do
    cond do
      candidate["base_revision_id"] != expected_revision ->
        {:error, :candidate_base_mismatch}

      review["candidate_id"] != candidate["id"] ->
        {:error, :review_candidate_mismatch}

      review["content_hash"] != candidate["content_hash"] ->
        {:error, :review_content_mismatch}

      true ->
        :ok
    end
  end

  defp validate_review(candidate, review) do
    cond do
      not is_binary(review["actor"]) or String.trim(review["actor"]) == "" ->
        {:error, :missing_actor}

      Map.get(candidate, "structural_errors", []) != [] ->
        {:error, :invalid_model}

      not is_list(Map.get(candidate, "checks", [])) or
          not Enum.all?(Map.get(candidate, "checks", []), &is_map/1) ->
        {:error, :invalid_check_results}

      not valid_overrides?(Map.get(review, "overrides", [])) ->
        {:error, :invalid_overrides}

      MapSet.new(Map.get(review, "report_ids", [])) !=
          MapSet.new(Map.get(candidate, "report_ids", [])) ->
        {:error, :review_reports_mismatch}

      true ->
        :ok
    end
  end

  defp valid_overrides?(overrides) when is_list(overrides) do
    Enum.all?(overrides, fn
      %{"constraint_id" => id, "reason" => reason}
      when is_binary(id) and is_binary(reason) ->
        id != "" and String.trim(reason) != ""

      _ ->
        false
    end)
  end

  defp valid_overrides?(_), do: false

  defp validate_checks(checks, overrides) when is_list(checks) do
    acknowledged = MapSet.new(overrides, & &1["constraint_id"])

    blockers =
      Enum.flat_map(checks, fn check ->
        required = check["severity"] == "required"
        status = check["status"]
        deterministic = check["evaluation"] == "deterministic"
        id = check["constraint_id"]

        cond do
          not required or status == "pass" ->
            []

          deterministic ->
            [%{"constraint_id" => id, "reason" => "hard_requirement_failed"}]

          not MapSet.member?(acknowledged, id) ->
            [
              %{
                "constraint_id" => id,
                "reason" => "review_acknowledgment_required",
                "status" => status
              }
            ]

          true ->
            []
        end
      end)

    if blockers == [], do: :ok, else: {:error, {:review_blockers, blockers}}
  end

  defp validate_checks(_, _), do: {:error, :invalid_check_results}
end
