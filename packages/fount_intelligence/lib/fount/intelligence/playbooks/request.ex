defmodule Fount.Intelligence.Playbooks.Request do
  @moduledoc "A closed, validated inspection request. No executable module, function or storage route can be supplied as data."
  alias Fount.Intelligence.Playbooks.Registry
  @enforce_keys [:id, :playbook, :params]
  defstruct [:id, :playbook, :params]
  @type t :: %__MODULE__{id: String.t(), playbook: String.t(), params: map()}

  def parse(model, %__MODULE__{} = request), do: parse(model, to_map(request))

  def parse(model, %{"id" => id, "playbook" => playbook, "params" => params} = input)
      when is_binary(id) and is_binary(playbook) and is_map(params) do
    with true <-
           id != "" and String.valid?(id) and Map.keys(input) -- ~w(id playbook params) == [],
         :ok <- Registry.validate(model, playbook, params) do
      {:ok, %__MODULE__{id: id, playbook: playbook, params: params}}
    else
      false -> {:error, :invalid_playbook_request}
      error -> error
    end
  end

  def parse(_, _), do: {:error, :invalid_playbook_request}

  def parse_many(model, requests) when is_list(requests) do
    Enum.reduce_while(requests, {:ok, [], MapSet.new()}, fn input, {:ok, acc, seen} ->
      with {:ok, request} <- parse(model, input), false <- MapSet.member?(seen, request.id) do
        {:cont, {:ok, acc ++ [request], MapSet.put(seen, request.id)}}
      else
        true -> {:halt, {:error, :duplicate_playbook_request_id}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values, _} -> {:ok, values}
      error -> error
    end
  end

  def parse_many(_, _), do: {:error, :request_array_required}

  def to_map(%__MODULE__{} = request),
    do: %{"id" => request.id, "playbook" => request.playbook, "params" => request.params}
end
