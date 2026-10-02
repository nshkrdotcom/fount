defmodule Fount.Screenplay.SourceReconciler do
  @moduledoc """
  Reconciles a complete Fountain working source with an existing `Fount.Screenplay`.

  This adapter exists for interactive authoring. It preserves the screenplay
  identity and uses the existing Fountain identity reconciler for unaffected
  source-backed nodes. It never persists or accepts a revision.
  """

  alias Fount.{Annotations, Diagnostic, ID, Identity, Revision, Screenplay}
  alias Fount.Screenplay.Model

  @default_max_bytes 1_048_576
  @blocking_warning_codes [:unclosed_boneyard, :unclosed_note]

  @type result :: %{
          screenplay: Screenplay.t(),
          document: Fount.Document.t(),
          diagnostics: [Diagnostic.t()],
          fidelity: map(),
          anchors: [map()],
          identity_anchors: [map()]
        }

  @spec reconcile(Screenplay.t(), binary(), keyword()) ::
          {:ok, result()} | {:error, term()}
  def reconcile(base, raw, opts \\ [])

  def reconcile(%Screenplay{} = base, raw, opts) when is_binary(raw) do
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)

    if byte_size(raw) > max_bytes do
      {:error, {:source_too_large, max_bytes}}
    else
      do_reconcile(base, raw, opts)
    end
  end

  def reconcile(%Screenplay{}, _raw, _opts), do: {:error, :source_must_be_binary}
  def reconcile(_, _, _), do: {:error, :screenplay_required}

  defp do_reconcile(base, raw, opts) do
    with {:ok, prior} <- source_document(base, opts),
         {:ok, document} <-
           Fount.reparse(prior, raw,
             actor: Keyword.get(opts, :actor),
             message: Keyword.get(opts, :message, "interactive source reconciliation")
           ) do
      diagnostics = diagnostics(document)

      case blocking_diagnostics(diagnostics) do
        [] ->
          model = build_model(base, document, raw, opts)

          {:ok,
           %{
             screenplay: model,
             document: document,
             diagnostics: diagnostics,
             fidelity: fidelity(base, model, prior, raw, diagnostics),
             anchors: anchors(document),
             identity_anchors: Identity.anchors(document.ir)
           }}

        blockers ->
          {:error, {:invalid_source, blockers, diagnostics}}
      end
    end
  end

  defp source_document(base, opts) do
    raw = Keyword.get(opts, :prior_source, Screenplay.to_fountain(base))
    identity_anchors = Keyword.get(opts, :identity_anchors, Identity.anchors(base.ir))

    Fount.parse(raw,
      document_id: base.id,
      identity_anchors: identity_anchors,
      annotations: base.annotations
    )
  end

  defp build_model(base, document, raw, opts) do
    revision = %Revision{
      id: Keyword.get(opts, :revision_id, ID.v4()),
      parent_id: base.revision.id,
      created_at: Keyword.get(opts, :created_at, DateTime.utc_now()),
      actor: Keyword.get(opts, :actor),
      message: Keyword.get(opts, :message, "interactive source reconciliation")
    }

    valid_ids = addressable_ids(base.id, document.ir)

    model =
      %{
        base
        | ir: document.ir,
          revision: revision,
          import: nil,
          annotations: Annotations.prune(base.annotations, valid_ids)
      }
      |> Model.refresh()

    import = %{
      format: :fountain,
      bytes: raw,
      revision_id: model.revision.id,
      render_hash: model.revision.render_hash,
      losses: []
    }

    %{model | import: import}
  end

  defp diagnostics(document) do
    (document.diagnostics ++ Fount.Validate.document(document))
    |> Enum.uniq_by(fn diagnostic ->
      span = diagnostic.span

      {
        diagnostic.severity,
        diagnostic.code,
        diagnostic.node_id,
        span && span.byte_start,
        span && span.byte_end
      }
    end)
  end

  defp blocking_diagnostics(diagnostics) do
    Enum.filter(diagnostics, fn diagnostic ->
      diagnostic.severity == :error or
        (diagnostic.severity == :warning and diagnostic.code in @blocking_warning_codes)
    end)
  end

  defp fidelity(base, model, prior, raw, diagnostics) do
    diff = Screenplay.diff(base, model)
    before_elements = MapSet.new(Enum.map(prior.ir.elements, & &1.id))
    after_elements = MapSet.new(Enum.map(model.ir.elements, & &1.id))
    before_cast = MapSet.new(Map.keys(base.cast))
    after_cast = MapSet.new(Map.keys(model.cast))

    %{
      "screenplay_id" => model.id,
      "base_revision_id" => base.revision.id,
      "result_revision_id" => model.revision.id,
      "source_sha256" => ID.hash(raw),
      "source_bytes" => byte_size(raw),
      "exact_source_round_trip" => Screenplay.to_fountain(model) == raw,
      "preserved_element_ids" =>
        before_elements |> MapSet.intersection(after_elements) |> MapSet.to_list() |> Enum.sort(),
      "added_element_ids" => diff.elements.added,
      "removed_element_ids" => diff.elements.removed,
      "changed_element_ids" => diff.elements.changed,
      "moved_scene_ids" => diff.scenes.moved,
      "preserved_cast_ids" => before_cast |> MapSet.intersection(after_cast) |> MapSet.to_list() |> Enum.sort(),
      "added_cast_ids" => after_cast |> MapSet.difference(before_cast) |> MapSet.to_list() |> Enum.sort(),
      "removed_cast_ids" => before_cast |> MapSet.difference(after_cast) |> MapSet.to_list() |> Enum.sort(),
      "diagnostic_count" => length(diagnostics)
    }
  end

  defp anchors(document) do
    Enum.flat_map(document.ir.elements, fn element ->
      case element.source_span do
        %{line_start: line_start, line_end: line_end} ->
          [
            %{
              "id" => element.id,
              "type" => Atom.to_string(element.type),
              "line_start" => line_start,
              "line_end" => line_end
            }
          ]

        _ ->
          []
      end
    end)
  end

  defp addressable_ids(screenplay_id, ir) do
    title_ids =
      case ir.title_page do
        nil -> []
        page -> Enum.map(page.entries, & &1.id)
      end

    [screenplay_id] ++
      Enum.map(ir.elements, & &1.id) ++
      Enum.map(ir.scenes, & &1.id) ++
      Enum.map(ir.dialogue_blocks, & &1.id) ++
      Enum.map(ir.outline, & &1.id) ++ title_ids
  end
end
