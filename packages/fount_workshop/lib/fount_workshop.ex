defmodule FountWorkshop do
  @moduledoc "Writer-controlled screenplay revision workflow over canonical model IDs."

  alias Fount.Source.Span
  alias FountWorkshop.{Preview, Proposal}

  @spec context(Fount.Document.t() | Fount.Screenplay.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def context(doc, scene_id, opts \\ [])

  def context(%Fount.Screenplay{} = screenplay, scene_id, opts) do
    case Fount.Screenplay.scene(screenplay, scene_id) do
      nil ->
        {:error, {:unknown_scene, scene_id}}

      scene ->
        elements = Enum.map(scene.element_ids, &Fount.Screenplay.node(screenplay, &1))
        scene_text = Enum.map_join(elements, "\n", &"#{&1.type}: #{&1.text}")

        if byte_size(scene_text) > Keyword.get(opts, :max_bytes, 24_000) do
          {:error, {:context_too_large, byte_size(scene_text)}}
        else
          {:ok,
           %{
             scene_id: scene.id,
             revision: screenplay.revision.id,
             source: scene_text,
             elements: Enum.map(elements, &Map.take(&1, [:id, :type, :text])),
             characters:
               Enum.map(Map.values(screenplay.cast), &Map.take(&1, [:id, :display_name]))
           }}
        end
    end
  end

  def context(doc, scene_id, opts) do
    case Fount.scene(doc, scene_id) do
      nil ->
        {:error, {:unknown_scene, scene_id}}

      scene ->
        elements = Enum.map(scene.element_ids, &Fount.node(doc, &1))
        max_bytes = Keyword.get(opts, :max_bytes, 24_000)
        source = Span.slice(doc.source.raw, scene.source_span)

        if byte_size(source) > max_bytes do
          {:error, {:context_too_large, byte_size(source)}}
        else
          {:ok,
           %{
             scene_id: scene.id,
             revision: doc.revision.id,
             source: source,
             elements: Enum.map(elements, &Map.take(&1, [:id, :type, :text])),
             characters: Fount.characters(doc)
           }}
        end
    end
  end

  @spec propose(map(), String.t(), Inference.Client.t(), keyword()) ::
          {:ok, Proposal.t()} | {:error, term()}
  def propose(context, instruction, client, opts \\ []) do
    request = Proposal.request(context, instruction)

    format =
      if Inference.Capability.supported?(
           Inference.capabilities(client),
           :response_format_json_schema
         ),
         do: Proposal.response_format(),
         else: :text

    opts = Keyword.put_new(opts, :response_format, format)

    with {:ok, response} <- Inference.complete(client, request, opts),
         {:ok, proposal} <- Proposal.decode(response.object || response.text, context) do
      {:ok,
       %{
         proposal
         | inference: %{
             provider: response.provider,
             model: response.model,
             response_id: response.id
           }
       }}
    end
  end

  @spec preview(Fount.Document.t() | Fount.Screenplay.t(), Proposal.t(), keyword()) ::
          {:ok, Preview.t()} | {:error, term()}
  def preview(doc, proposal, opts \\ [])

  def preview(%Fount.Screenplay{} = screenplay, %Proposal{} = proposal, _opts) do
    with :ok <- current_revision(screenplay, proposal.base_revision),
         {:ok, changed} <- Fount.Screenplay.apply(screenplay, proposal.operations) do
      {:ok,
       %Preview{
         document: changed,
         change_set: %{
           operations: proposal.operations,
           before_revision: screenplay.revision.id,
           after_revision: changed.revision.id
         },
         base_revision: proposal.base_revision,
         source_diff:
           String.myers_difference(
             Fount.Screenplay.to_fountain(screenplay),
             Fount.Screenplay.to_fountain(changed)
           ),
         semantic_diff: Fount.Screenplay.diff(screenplay, changed),
         diagnostics: [],
         inference: proposal.inference
       }}
    end
  end

  def preview(doc, %Proposal{} = proposal, opts) do
    with :ok <- current_revision(doc, proposal.base_revision),
         {:ok, changed, change_set} <- Fount.apply(doc, proposal.operations, opts) do
      diagnostics = Fount.validate(changed)

      if Enum.any?(diagnostics, &(&1.severity == :error)) do
        {:error, {:invalid_screenplay, diagnostics}}
      else
        {:ok,
         %Preview{
           document: changed,
           change_set: change_set,
           base_revision: proposal.base_revision,
           source_diff: Fount.Diff.source(doc, changed),
           semantic_diff: Fount.Diff.semantic(doc, changed),
           diagnostics: diagnostics,
           inference: proposal.inference
         }}
      end
    end
  end

  @spec accept(struct(), String.t(), Preview.t(), String.t(), keyword()) ::
          :ok | {:error, term()}
  def accept(store, key, preview, expected_revision, opts \\ [])

  def accept(
        Fount.Repo,
        key,
        %Preview{document: %Fount.Screenplay{}} = preview,
        expected_revision,
        opts
      ) do
    with :ok <- current_revision(preview, expected_revision) do
      Fount.Persistence.save(
        Fount.Repo,
        key,
        preview.document,
        Keyword.merge(opts,
          expected_revision: expected_revision,
          acceptance: %{inference: preview.inference, operations: preview.change_set.operations}
        )
      )
    end
  end

  def accept(store, key, %Preview{} = preview, expected_revision, opts) do
    with :ok <- FountWorkshop.Acceptance.supported?(store),
         :ok <- current_revision(preview, expected_revision),
         :ok <-
           Fount.Store.save(
             store,
             key,
             preview.document,
             Keyword.put(opts, :expected_revision, expected_revision)
           ) do
      FountWorkshop.Acceptance.record(store, key, preview)
    end
  end

  defp current_revision(%Preview{base_revision: base}, expected),
    do: current_revision(base, expected)

  defp current_revision(%Fount.Document{revision: %{id: actual}}, expected),
    do: current_revision(actual, expected)

  defp current_revision(%Fount.Screenplay{revision: %{id: actual}}, expected),
    do: current_revision(actual, expected)

  defp current_revision(expected, expected), do: :ok
  defp current_revision(actual, _expected), do: {:error, {:stale_revision, actual}}
end
