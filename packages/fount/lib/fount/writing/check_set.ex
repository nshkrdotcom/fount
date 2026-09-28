defmodule Fount.Writing.CheckSet do
  @moduledoc """
  Builds the authoritative required-check inventory stored with a candidate.

  Required identities come from persisted operation/constraint configuration and
  application checks, not from a caller's later review payload. The fingerprint
  covers required definitions, every stored outcome, and exact report IDs.
  """

  alias Fount.Screenplay.Model
  alias Fount.Writing.CanonicalJSON

  @spec snapshot(map(), map()) :: {:ok, map()} | {:error, term()}
  def snapshot(session, provenance) when is_map(session) and is_map(provenance) do
    checks = Map.get(provenance, "checks", [])
    application_checks = Map.get(provenance, "application_checks", [])
    report_ids = Map.get(provenance, "report_ids", [])
    constraints = trusted_constraints(session, provenance)
    overridable = overridable_ids(session)

    with :ok <- validate_checks(checks),
         :ok <- validate_checks(application_checks),
         :ok <- validate_cross_check_identity(checks, application_checks),
         :ok <- validate_report_ids(report_ids),
         all_checks = merge_checks(checks, application_checks),
         {:ok, required} <- required_inventory(constraints, application_checks, checks, overridable),
         :ok <- ensure_required_results(required, all_checks) do
      payload = %{
        "required_checks" => required,
        "checks" => Model.plain(all_checks),
        "report_ids" => report_ids
      }

      {:ok,
       %{
         "required_checks" => required,
         "check_set_fingerprint" => CanonicalJSON.hash(payload)
       }}
    end
  end

  def snapshot(_, _), do: {:error, :invalid_check_set}

  @spec validate_stored(map(), list(), list(), String.t()) :: :ok | {:error, term()}
  def validate_stored(candidate, checks, report_ids, fingerprint)
      when is_map(candidate) and is_list(checks) and is_list(report_ids) and is_binary(fingerprint) do
    required = Map.get(candidate, "required_checks") || []

    with :ok <- validate_required(required),
         :ok <- validate_checks(checks),
         :ok <- validate_report_ids(report_ids),
         :ok <- ensure_required_results(required, checks) do
      actual =
        CanonicalJSON.hash(%{
          "required_checks" => required,
          "checks" => Model.plain(checks),
          "report_ids" => report_ids
        })

      if actual == fingerprint, do: :ok, else: {:error, :check_set_fingerprint_mismatch}
    end
  end

  def validate_stored(_, _, _, _), do: {:error, :invalid_check_set}

  defp merge_checks(checks, application_checks) do
    seen = MapSet.new(Enum.map(checks, &Map.get(&1, "constraint_id")))
    checks ++ Enum.reject(application_checks, &MapSet.member?(seen, Map.get(&1, "constraint_id")))
  end

  defp validate_cross_check_identity(checks, application_checks) do
    application_by_id = Map.new(application_checks, &{&1["constraint_id"], &1})

    if Enum.any?(checks, &conflicts_with_application?(&1, application_by_id)),
      do: {:error, :conflicting_check_results},
      else: :ok
  end

  defp conflicts_with_application?(check, application_by_id) do
    case Map.fetch(application_by_id, check["constraint_id"]) do
      {:ok, application_check} -> application_check != check
      :error -> false
    end
  end

  defp trusted_constraints(session, provenance) do
    request = Map.get(session, "request", %{})
    request_constraints = if is_map(request), do: Map.get(request, "constraints", []), else: []
    provenance_constraints = Map.get(provenance, "constraints", [])

    (List.wrap(request_constraints) ++ List.wrap(provenance_constraints))
    |> Enum.filter(&is_map/1)
    |> Enum.uniq_by(&Map.get(&1, "id"))
  end

  defp overridable_ids(session) do
    case get_in(session, ["request", "approval", "overridable_constraint_ids"]) do
      ids when is_list(ids) -> MapSet.new(Enum.filter(ids, &nonblank?/1))
      _ -> MapSet.new()
    end
  end

  defp required_inventory(constraints, application_checks, checks, overridable) do
    constraint_defs =
      constraints
      |> Enum.filter(&(Map.get(&1, "severity") == "required"))
      |> Enum.map(fn constraint ->
        id = Map.get(constraint, "id")
        evaluation = constraint_evaluation(constraint)

        %{
          "constraint_id" => id,
          "evaluation" => evaluation,
          "overridable" => evaluation == "semantic" and MapSet.member?(overridable, id)
        }
      end)

    application_defs =
      application_checks
      |> Enum.filter(&(Map.get(&1, "severity") == "required"))
      |> Enum.map(&check_definition(&1, overridable))

    fallback_defs =
      checks
      |> Enum.filter(&(Map.get(&1, "severity") == "required"))
      |> Enum.map(&check_definition(&1, overridable))

    required =
      (constraint_defs ++ application_defs ++ fallback_defs)
      |> Enum.reduce(%{}, fn definition, acc ->
        case definition do
          %{"constraint_id" => id} when is_binary(id) and id != "" -> Map.put_new(acc, id, definition)
          _ -> Map.put(acc, :invalid, definition)
        end
      end)

    cond do
      Map.has_key?(required, :invalid) ->
        {:error, :invalid_required_check}

      Enum.any?(Map.values(required), &(Map.get(&1, "evaluation") not in ["deterministic", "semantic", "external"])) ->
        {:error, :unknown_check_evaluation}

      true ->
        {:ok, required |> Map.values() |> Enum.sort_by(& &1["constraint_id"])}
    end
  end

  defp check_definition(check, overridable) do
    id = Map.get(check, "constraint_id")
    evaluation = Map.get(check, "evaluation")

    %{
      "constraint_id" => id,
      "evaluation" => evaluation,
      "overridable" => evaluation == "semantic" and MapSet.member?(overridable, id)
    }
  end

  defp constraint_evaluation(%{"kind" => "semantic"}), do: "semantic"

  defp constraint_evaluation(%{"kind" => "invention_policy", "spec" => %{"prohibited_facts" => facts}})
       when is_list(facts) and facts != [],
       do: "semantic"

  defp constraint_evaluation(%{"kind" => "page_goal"}), do: "external"
  defp constraint_evaluation(_), do: "deterministic"

  defp ensure_required_results(required, checks) do
    grouped = Enum.group_by(checks, &Map.get(&1, "constraint_id"))

    cond do
      Enum.any?(grouped, fn {id, values} -> not nonblank?(id) or length(values) != 1 end) ->
        {:error, :duplicate_or_invalid_check_result}

      Enum.any?(required, fn definition ->
        case Map.get(grouped, definition["constraint_id"]) do
          [check] ->
            Map.get(check, "evaluation") != definition["evaluation"] or
                Map.get(check, "severity") != "required"

          _ ->
            true
        end
      end) ->
        {:error, :missing_required_check}

      true ->
        :ok
    end
  end

  defp validate_required(required) when is_list(required) do
    ids = Enum.map(required, &Map.get(&1, "constraint_id"))

    if Enum.all?(required, fn item ->
         is_map(item) and nonblank?(item["constraint_id"]) and
           item["evaluation"] in ["deterministic", "semantic", "external"] and
           is_boolean(item["overridable"])
       end) and length(ids) == length(Enum.uniq(ids)) do
      :ok
    else
      {:error, :invalid_required_check_inventory}
    end
  end

  defp validate_required(_), do: {:error, :invalid_required_check_inventory}

  defp validate_checks(checks) when is_list(checks) do
    if Enum.all?(checks, fn check ->
         is_map(check) and nonblank?(check["constraint_id"]) and
           check["severity"] in ["required", "advisory"] and
           check["evaluation"] in ["deterministic", "semantic", "external"] and
           nonblank?(check["status"])
       end) do
      :ok
    else
      {:error, :invalid_check_results}
    end
  end

  defp validate_checks(_), do: {:error, :invalid_check_results}

  defp validate_report_ids(ids) when is_list(ids) do
    if Enum.all?(ids, &nonblank?/1) and length(ids) == length(Enum.uniq(ids)),
      do: :ok,
      else: {:error, :invalid_review_reports}
  end

  defp validate_report_ids(_), do: {:error, :invalid_review_reports}
  defp nonblank?(value), do: is_binary(value) and String.trim(value) != ""
end
