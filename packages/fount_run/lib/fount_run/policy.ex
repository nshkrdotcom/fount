defmodule FountRun.Policy do
  @moduledoc "Closed, canonical Run policy validation and trusted approver resolution."

  alias Fount.Writing.{CanonicalJSON, Principal}
  alias FountRun.{ActorContext, ClosedMap}

  @keys ~w(gates completion approver fallback_approver route_choice limits)
  @gate_keys ~w(investigation_scope strategy_choice candidate_generation iteration)
  @route_keys ~w(rule reviewer_id)
  @limit_keys ~w(max_iterations max_malformed_repairs_per_call max_transient_retries max_inference_calls max_measurement_states money)
  @money_keys ~w(currency max_microunits)
  @gate_values ~w(automatic human)
  @defaults %{
    "max_iterations" => 3,
    "max_malformed_repairs_per_call" => 1,
    "max_transient_retries" => 2,
    "max_inference_calls" => 12,
    "max_measurement_states" => 500,
    "money" => nil
  }

  @enforce_keys [:value, :fingerprint, :author]
  defstruct @enforce_keys
  @type t :: %__MODULE__{value: map(), fingerprint: String.t(), author: Principal.t()}

  @spec new(map(), ActorContext.t()) :: {:ok, t()} | {:error, term()}
  def new(value, %ActorContext{} = context) do
    with {:ok, value} <- ClosedMap.normalize(value, @keys),
         {:ok, gates} <- gates(Map.get(value, "gates")),
         {:ok, completion} <- completion(Map.get(value, "completion")),
         {:ok, approver} <- principal(Map.get(value, "approver"), context, :approver),
         {:ok, fallback} <- fallback(Map.get(value, "fallback_approver"), context),
         {:ok, route} <- route_choice(Map.get(value, "route_choice"), context),
         {:ok, limits} <- limits(Map.get(value, "limits", %{})),
         :ok <- completion_consistency(completion, approver, fallback) do
      resolved = %{
        "gates" => gates,
        "completion" => completion,
        "approver" => principal_map(approver),
        "fallback_approver" => principal_map(fallback),
        "route_choice" => route,
        "limits" => limits
      }

      {:ok,
       %__MODULE__{
         value: resolved,
         fingerprint: CanonicalJSON.hash(resolved),
         author: context.principal
       }}
    end
  end

  defp gates(nil), do: {:error, {:missing_field, "gates"}}

  defp gates(value) do
    with {:ok, value} <- ClosedMap.normalize(value, @gate_keys),
         true <- Enum.sort(Map.keys(value)) == Enum.sort(@gate_keys),
         true <- Enum.all?(@gate_keys, &(Map.get(value, &1) in @gate_values)) do
      {:ok, value}
    else
      false -> {:error, :invalid_gates}
      {:error, _} = error -> error
    end
  end

  defp completion(value) when value in ["candidate", "accept", "nonmutating"], do: {:ok, value}
  defp completion(_), do: {:error, :invalid_completion}

  defp principal(nil, _context, _label), do: {:ok, nil}

  defp principal(value, context, label) do
    with {:ok, value} <- ClosedMap.normalize(value, ~w(type id)),
         {:ok, principal} <- Principal.from_map(value),
         true <- ActorContext.allowed_approver?(context, principal) do
      {:ok, principal}
    else
      false -> {:error, {:unauthorized_principal, label}}
      {:error, _} = error -> error
    end
  end

  defp fallback(nil, _context), do: {:ok, nil}

  defp fallback(value, context) do
    with {:ok, principal} <- principal(value, context, :fallback_approver),
         true <- principal.type == :human and ActorContext.owner?(context, principal) do
      {:ok, principal}
    else
      false -> {:error, :fallback_must_be_owner}
      {:error, _} = error -> error
    end
  end

  defp route_choice(nil, _context), do: {:error, {:missing_field, "route_choice"}}

  defp route_choice(value, context) do
    with {:ok, value} <- ClosedMap.normalize(value, @route_keys) do
      route_choice_rule(value, context)
    end
  end

  defp route_choice_rule(value, context) do
    case Map.get(value, "rule") do
      "pause_on_material_tradeoff" ->
        if Map.has_key?(value, "reviewer_id"),
          do: {:error, :unexpected_route_reviewer},
          else: {:ok, value}

      "registered_reviewer" ->
        reviewer = Map.get(value, "reviewer_id")

        if ActorContext.allowed_route_reviewer?(context, reviewer),
          do: {:ok, value},
          else: {:error, :unregistered_route_reviewer}

      _ ->
        {:error, :invalid_route_choice}
    end
  end

  defp limits(value) do
    with {:ok, value} <- ClosedMap.normalize(value, @limit_keys),
         value = Map.merge(@defaults, value),
         true <- valid_limits?(value),
         {:ok, money} <- money(Map.get(value, "money")) do
      {:ok, Map.put(value, "money", money)}
    else
      false -> {:error, :invalid_limits}
      error -> error
    end
  end

  defp valid_limits?(value) do
    Enum.all?(@limit_keys -- ["money"], fn key ->
      limit = Map.get(value, key)
      is_integer(limit) and limit >= 0
    end)
  end

  defp money(nil), do: {:ok, nil}

  defp money(value) do
    with {:ok, value} <- ClosedMap.normalize(value, @money_keys),
         true <- Enum.sort(Map.keys(value)) == Enum.sort(@money_keys),
         currency when is_binary(currency) <- Map.get(value, "currency"),
         true <- Regex.match?(~r/^[A-Z]{3}$/, currency),
         microunits when is_integer(microunits) and microunits >= 0 <-
           Map.get(value, "max_microunits") do
      {:ok, value}
    else
      _ -> {:error, :invalid_money_limit}
    end
  end

  defp completion_consistency("candidate", nil, nil), do: :ok
  defp completion_consistency("nonmutating", nil, nil), do: :ok
  defp completion_consistency("candidate", _, _), do: {:error, :candidate_completion_has_approver}

  defp completion_consistency("nonmutating", _, _),
    do: {:error, :nonmutating_completion_has_approver}

  defp completion_consistency("accept", %Principal{}, _), do: :ok

  defp completion_consistency("accept", nil, _),
    do: {:error, :accept_completion_requires_approver}

  defp principal_map(nil), do: nil
  defp principal_map(%Principal{} = principal), do: Principal.to_map(principal)
end
