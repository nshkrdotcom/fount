defmodule Fount.Semantics.SourceReview do
  @moduledoc "Pure validation for source-bound manual interpretation review commands."

  @actions ~w(confirm reject change_type merge split set_alias resolve_occurrence set_location_parent set_time undo)
  @kinds ~w(character location document_text prop organization unknown)
  @roles ~w(speaker physical_presence mentioned printed_text message_sender location_heading location_reference unknown)

  def actions, do: @actions
  def kinds, do: @kinds
  def roles, do: @roles

  def validate_command(command) when is_map(command) do
    action = value(command, "action")
    target = value(command, "target_handle_id")
    payload = value(command, "payload") || %{}

    cond do
      action not in @actions -> {:error, :invalid_review_action}
      action != "undo" and not uuid?(target) -> {:error, :invalid_review_target}
      not is_map(payload) -> {:error, :invalid_review_payload}
      true -> validate_payload(action, payload)
    end
  end

  def validate_command(_), do: {:error, :invalid_review_command}

  defp validate_payload(action, payload) when action in ~w(confirm reject), do: closed(payload, [])

  defp validate_payload("change_type", %{"kind" => kind} = payload) do
    if kind in @kinds, do: closed(payload, ["kind"]), else: {:error, :invalid_entity_kind}
  end

  defp validate_payload("merge", %{"into_handle_id" => id} = payload) do
    if uuid?(id), do: closed(payload, ["into_handle_id"]), else: {:error, :invalid_merge_target}
  end

  defp validate_payload("split", %{"local_ids" => ids} = payload) when is_list(ids) and ids != [] do
    if Enum.all?(ids, &(is_binary(&1) and &1 != "")), do: closed(payload, ["local_ids"]), else: {:error, :invalid_split_occurrences}
  end

  defp validate_payload("set_alias", %{"alias" => alias_text} = payload) when is_binary(alias_text) do
    if String.trim(alias_text) != "", do: closed(payload, ["alias"]), else: {:error, :invalid_alias}
  end

  defp validate_payload("resolve_occurrence", %{"local_id" => local_id, "role" => role} = payload) do
    cond do
      not is_binary(local_id) or local_id == "" -> {:error, :invalid_occurrence}
      role not in @roles -> {:error, :invalid_occurrence_role}
      true -> closed(payload, ["local_id", "role"])
    end
  end

  defp validate_payload("set_location_parent", %{"parent_handle_id" => id} = payload) do
    if uuid?(id), do: closed(payload, ["parent_handle_id"]), else: {:error, :invalid_location_parent}
  end

  defp validate_payload("set_time", %{"value" => value} = payload) when is_binary(value) do
    if String.trim(value) != "", do: closed(payload, ["value"]), else: {:error, :invalid_time_value}
  end

  defp validate_payload("undo", %{"event_id" => id} = payload) do
    if uuid?(id), do: closed(payload, ["event_id"]), else: {:error, :invalid_undo_event}
  end

  defp validate_payload(_, _), do: {:error, :invalid_review_payload}

  defp closed(payload, keys) do
    if Map.keys(payload) |> Enum.sort() == Enum.sort(keys), do: :ok, else: {:error, :unknown_review_payload_field}
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, String.to_atom(key)))

  defp uuid?(value) when is_binary(value),
    do: Regex.match?(~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i, value)

  defp uuid?(_), do: false
end
