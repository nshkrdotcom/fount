defmodule Fount.Observe.Request do
  @moduledoc "Separates effective semantic input from current-revision target, evidence and provenance."
  alias Fount.Observe.{Context, Error, EvidenceRef, TargetRef}
  alias Fount.Writing.CanonicalJSON
  @enforce_keys [:id, :input, :target]
  defstruct [:id, :input, :target, context: %Context{}, evidence: [], projection_id: "explicit_state", provenance: %{}]
  @type t :: %__MODULE__{}

  def new(model, id, input, opts \\ []) do
    with true <- is_list(opts) and Keyword.keyword?(opts) and
           Keyword.keys(opts) -- [:target, :evidence, :context, :projection_id, :provenance] == [],
         true <- is_struct(model, Fount.Screenplay),
         true <- is_binary(id) and id != "" and String.valid?(id),
         {:ok, _} <- CanonicalJSON.encode(input),
         {:ok, target} <- TargetRef.from_source(model, Keyword.get(opts, :target, %{"kind" => "semantic_subject", "id" => id})),
         {:ok, evidence} <- evidence(model, Keyword.get(opts, :evidence, [])),
         %Context{} = context <- Keyword.get(opts, :context, %Context{}),
         {:ok, _} <- CanonicalJSON.encode(Keyword.get(opts, :provenance, %{})) do
      {:ok, %__MODULE__{id: id, input: input, target: target, context: context,
        evidence: evidence, projection_id: Keyword.get(opts, :projection_id, "explicit_state"),
        provenance: Keyword.get(opts, :provenance, %{})}}
    else
      {:error, %Error{} = error} -> {:error, %{error | request_id: id}}
      _ -> {:error, Error.new(:invalid_request, if(is_binary(id), do: id))}
    end
  end

  defp evidence(model, entries) when is_list(entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
      case EvidenceRef.from_source(model, entry) do
        {:ok, ref} -> {:cont, {:ok, acc ++ [ref]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, refs} -> if(length(Enum.uniq_by(refs, & &1.id)) == length(refs), do: {:ok, refs}, else: {:error, Error.new(:invalid_target)})
      error -> error
    end
  end
  defp evidence(_, _), do: {:error, Error.new(:invalid_target)}
end
