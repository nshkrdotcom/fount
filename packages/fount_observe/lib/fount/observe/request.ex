defmodule Fount.Observe.Request do
  @moduledoc "Separates effective semantic input from current-revision target, evidence and provenance."
  alias Fount.Observe.{Context, Error, EvidenceRef, Registry, TargetRef}
  alias Fount.Writing.CanonicalJSON
  @enforce_keys [:id, :input, :target]
  defstruct [
    :id,
    :input,
    :target,
    context: %Context{},
    evidence: [],
    projection_id: "explicit_state",
    provenance: %{}
  ]

  @type t :: %__MODULE__{}

  def new(model, id, input, opts \\ []) do
    with true <-
           is_list(opts) and Keyword.keyword?(opts) and
             Keyword.keys(opts) -- [:target, :evidence, :context, :projection_id, :provenance] ==
               [],
         true <- is_struct(model, Fount.Screenplay),
         true <- is_binary(id) and id != "" and String.valid?(id),
         {:ok, _} <- CanonicalJSON.encode(input),
         {:ok, target} <-
           TargetRef.from_source(
             model,
             Keyword.get(opts, :target, %{"kind" => "semantic_subject", "id" => id})
           ),
         {:ok, evidence} <- evidence(model, Keyword.get(opts, :evidence, [])),
         %Context{} = context <- Keyword.get(opts, :context, %Context{}),
         true <- is_map(Keyword.get(opts, :provenance, %{})),
         {:ok, _} <- CanonicalJSON.encode(Keyword.get(opts, :provenance, %{})),
         true <- Registry.projection?(Keyword.get(opts, :projection_id, "explicit_state")) do
      {:ok,
       %__MODULE__{
         id: id,
         input: input,
         target: target,
         context: context,
         evidence: evidence,
         projection_id: Keyword.get(opts, :projection_id, "explicit_state"),
         provenance: Keyword.get(opts, :provenance, %{})
       }}
    else
      {:error, %Error{} = error} -> {:error, %{error | request_id: id}}
      _ -> {:error, Error.new(:invalid_request, if(is_binary(id), do: id))}
    end
  end


  @doc "The exact canonical bytes submitted to a provider and used as semantic cache identity."
  def semantic_input(%__MODULE__{} = request), do: CanonicalJSON.encode!(%{
    "state" => request.input, "context" => Context.semantic_map(request.context)})
  def input_hash(%__MODULE__{} = request), do:
    :crypto.hash(:sha256, semantic_input(request)) |> Base.encode16(case: :lower)

  @doc "Current revision dependencies; never included in reusable result identity."
  def dependencies(%__MODULE__{} = request) do
    [%{"kind" => "target", "target" => TargetRef.to_map(request.target)}] ++
      Enum.map(request.evidence, fn ref -> %{"kind" => "evidence", "id" => ref.id,
        "target" => TargetRef.to_map(ref.target), "excerpt_sha256" => ref.excerpt_sha256} end)
  end

  @doc false
  def validate_envelope(%__MODULE__{target: %TargetRef{} = target} = request) do
    valid = Enum.all?([target.screenplay_id, target.revision_id, target.kind, target.id],
      &(is_binary(&1) and &1 != "" and String.valid?(&1))) and
      target.kind in ~w(screenplay scene element dialogue_block character semantic_subject) and
      Registry.projection?(request.projection_id) and is_list(request.evidence) and
      Enum.all?(request.evidence, fn
        %EvidenceRef{target: %TargetRef{} = source} = ref ->
          ref.screenplay_id == target.screenplay_id and ref.revision_id == target.revision_id and
            source.screenplay_id == target.screenplay_id and source.revision_id == target.revision_id and
            is_binary(ref.id) and ref.id != "" and String.valid?(ref.id) and
            is_binary(ref.role) and String.valid?(ref.role) and
            is_binary(ref.excerpt) and String.valid?(ref.excerpt) and
            ref.excerpt_sha256 == (:crypto.hash(:sha256, ref.excerpt) |> Base.encode16(case: :lower))
        _ -> false
      end) and
      length(Enum.uniq_by(request.evidence, & &1.id)) == length(request.evidence) and
      Context.evidence_ids(request.context) -- Enum.map(request.evidence, & &1.id) == [] and
      is_map(request.provenance) and match?({:ok, _}, CanonicalJSON.encode(request.provenance))
    if valid, do: :ok, else: {:error, Error.new(:invalid_target)}
  rescue
    _ -> {:error, Error.new(:invalid_target)}
  end
  def validate_envelope(_), do: {:error, Error.new(:invalid_target)}

  defp evidence(model, entries) when is_list(entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
      case EvidenceRef.from_source(model, entry) do
        {:ok, ref} -> {:cont, {:ok, acc ++ [ref]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, refs} ->
        if(length(Enum.uniq_by(refs, & &1.id)) == length(refs),
          do: {:ok, refs},
          else: {:error, Error.new(:invalid_target)}
        )

      error ->
        error
    end
  end

  defp evidence(_, _), do: {:error, Error.new(:invalid_target)}
end
