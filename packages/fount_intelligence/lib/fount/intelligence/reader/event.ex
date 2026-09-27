defmodule Fount.Intelligence.Reader.Event do
  @moduledoc """
  Source-backed presentation event consumed by the pure forward Reader reducer.

  `claim_class` keeps deterministic ledger updates separate from model-estimated
  interpretation. Human-calibrated claims are not created by this reducer. When
  multiple events share one presentation point, their order in the input list is
  the explicit update order.
  """

  alias Fount.Screenplay.Model

  @claim_classes ~w(canonical_fact deterministic_derived_narrative_state model_estimated_reader_interpretation)
  @visibilities ~w(reader_visible private)

  @enforce_keys [:id, :kind, :action, :point, :claim_class]
  defstruct [
    :id,
    :kind,
    :action,
    :point,
    :key,
    :claim_class,
    visibility: "reader_visible",
    data: %{},
    evidence: [],
    dependencies: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{}

  def new(%__MODULE__{} = event), do: validate(event)
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(%{} = attrs) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

    event = %__MODULE__{
      id: attrs["id"],
      kind: scalar(attrs["kind"]),
      action: scalar(attrs["action"]),
      point: attrs["point"],
      key: attrs["key"],
      claim_class: scalar(attrs["claim_class"]),
      visibility: scalar(attrs["visibility"] || "reader_visible"),
      data: Model.plain(attrs["data"] || %{}),
      evidence: List.wrap(attrs["evidence"]),
      dependencies:
        attrs["dependencies"]
        |> List.wrap()
        |> Enum.map(&to_string/1)
        |> Enum.uniq()
        |> Enum.sort(),
      metadata: Model.plain(attrs["metadata"] || %{})
    }

    validate(event)
  end

  def new(_attrs), do: {:error, :invalid_reader_event}

  defp validate(%__MODULE__{} = event) do
    cond do
      not nonempty?(event.id) ->
        {:error, :invalid_reader_event_id}

      not nonempty?(event.kind) ->
        {:error, {:invalid_reader_event_kind, event.id}}

      not nonempty?(event.action) ->
        {:error, {:invalid_reader_event_action, event.id}}

      not nonempty?(event.point) ->
        {:error, {:invalid_reader_event_point, event.id}}

      event.claim_class not in @claim_classes ->
        {:error, {:invalid_reader_claim_class, event.id}}

      event.visibility not in @visibilities ->
        {:error, {:invalid_reader_visibility, event.id}}

      true ->
        validate_maps(event)
    end
  end

  defp validate_maps(event) do
    cond do
      not is_map(event.data) ->
        {:error, {:invalid_reader_event_data, event.id}}

      not is_map(event.metadata) ->
        {:error, {:invalid_reader_event_metadata, event.id}}

      true ->
        {:ok, event}
    end
  end

  defp nonempty?(value), do: is_binary(value) and value != ""
  defp scalar(value) when is_atom(value), do: Atom.to_string(value)
  defp scalar(value) when is_binary(value), do: value
  defp scalar(value), do: value
end
