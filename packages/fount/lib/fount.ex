defmodule Fount do
  @moduledoc """
  Headless screenplay framework with lossless Fountain source, semantic IR,
  explicit edits, derived annotations, adapters, and pluggable persistence.
  """

  alias Fount.{Annotations, Document, ID, Identity, Index, Revision}
  alias Fount.Fountain.{CST, Parser, Scanner}

  @version "0.1.0"

  @spec version() :: String.t()
  def version, do: @version

  @spec parse(binary(), keyword()) :: {:ok, Document.t()} | {:error, term()}
  def parse(raw, opts \\ []) when is_binary(raw) do
    document_id = Keyword.get(opts, :document_id, ID.v4())
    source = Scanner.scan(raw, path: Keyword.get(opts, :path))
    {cst, ir, diagnostics} = Parser.parse(source, document_id, opts)

    {ir, id_map} =
      cond do
        prior = Keyword.get(opts, :prior) ->
          Identity.reconcile_with_map(prior.ir, ir, Keyword.get(opts, :identity_hints, []))

        anchors = Keyword.get(opts, :identity_anchors) ->
          Identity.restore_with_map(ir, anchors)

        true ->
          {ir, %{}}
      end

    cst = CST.remap_ids(cst, id_map, document_id)

    revision =
      Revision.from_source(raw,
        parent_id: Keyword.get(opts, :parent_revision_id),
        actor: Keyword.get(opts, :actor),
        message: Keyword.get(opts, :message),
        created_at: Keyword.get(opts, :revision_created_at, DateTime.utc_now())
      )

    annotations =
      opts
      |> Keyword.get(:annotations, Annotations.new())
      |> Annotations.prune(addressable_ids(ir))

    doc = %Document{
      id: document_id,
      revision: revision,
      source: source,
      cst: cst,
      ir: ir,
      annotations: annotations,
      diagnostics: diagnostics,
      index: Index.build(ir)
    }

    {:ok, doc}
  rescue
    exception -> {:error, {exception, __STACKTRACE__}}
  end

  @spec parse!(binary(), keyword()) :: Document.t()
  def parse!(raw, opts \\ []) do
    case parse(raw, opts) do
      {:ok, doc} -> doc
      {:error, reason} -> raise "Fount parse failed: #{inspect(reason)}"
    end
  end

  @spec parse_file(Path.t(), keyword()) :: {:ok, Document.t()} | {:error, term()}
  def parse_file(path, opts \\ []) do
    with {:ok, raw} <- File.read(path) do
      parse(raw, Keyword.put(opts, :path, path))
    end
  end

  @doc "Exact source rendering reconstructed from the byte-covering CST."
  @spec render(Document.t(), keyword()) :: binary()
  def render(%Document{source: %{format: :fountain}, cst: cst}, _opts \\ []), do: CST.render(cst)

  @doc "Canonical serialization from IR, for projections and adapter use."
  @spec serialize(Document.t(), keyword()) :: binary()
  def serialize(%Document{ir: ir}, opts \\ []), do: Fount.Fountain.Serializer.serialize(ir, opts)

  @spec reparse(Document.t(), binary(), keyword()) :: {:ok, Document.t()} | {:error, term()}
  def reparse(%Document{} = prior, new_raw, opts \\ []) do
    parse(new_raw,
      Keyword.merge(opts,
        document_id: prior.id,
        prior: prior,
        parent_revision_id: prior.revision.id,
        annotations: prior.annotations
      )
    )
  end

  defdelegate scenes(doc), to: Fount.Query
  defdelegate elements(doc), to: Fount.Query
  defdelegate elements(doc, type), to: Fount.Query
  defdelegate node(doc, id), to: Fount.Query
  defdelegate scene(doc, id), to: Fount.Query
  defdelegate dialogue_block(doc, id), to: Fount.Query
  defdelegate dialogue_blocks(doc), to: Fount.Query
  defdelegate node_at(doc, byte_offset), to: Fount.Query
  defdelegate scene_for(doc, element_id), to: Fount.Query
  defdelegate outline(doc), to: Fount.Query
  defdelegate nodes_in_span(doc, span), to: Fount.Query
  defdelegate search_text(doc, needle), to: Fount.Query
  defdelegate characters(doc), to: Fount.Query
  defdelegate character_cues(doc, name), to: Fount.Query

  @spec analyze(Document.t(), module(), keyword()) :: {:ok, Document.t()} | {:error, term()}
  def analyze(%Document{} = doc, analyzer, opts \\ []) do
    with {:ok, annotations} <- analyzer.analyze(doc, opts) do
      {:ok, %{doc | annotations: Annotations.put_many(doc.annotations, annotations)}}
    end
  end

  @spec validate(Document.t()) :: [Fount.Diagnostic.t()]
  def validate(%Document{} = doc), do: doc.diagnostics ++ Fount.Validate.document(doc)

  @spec apply(Document.t(), Fount.Edit.Op.t() | [Fount.Edit.Op.t()], keyword()) ::
          {:ok, Document.t(), Fount.Edit.ChangeSet.t()} | {:error, term()}
  def apply(%Document{} = doc, operations, opts \\ []), do: Fount.Edit.apply(doc, operations, opts)

  @spec undo(Document.t(), Fount.Edit.ChangeSet.t()) :: {:ok, Document.t()} | {:error, term()}
  def undo(%Document{} = doc, %Fount.Edit.ChangeSet{} = change_set), do: Fount.Edit.undo(doc, change_set)

  @spec redo(Document.t(), Fount.Edit.ChangeSet.t()) :: {:ok, Document.t()} | {:error, term()}
  def redo(%Document{} = doc, %Fount.Edit.ChangeSet{} = change_set), do: Fount.Edit.redo(doc, change_set)

  defp addressable_ids(ir) do
    title_ids =
      case ir.title_page do
        nil -> []
        page -> Enum.map(page.entries, & &1.id)
      end

    Enum.map(ir.elements, & &1.id) ++
      Enum.map(ir.scenes, & &1.id) ++
      Enum.map(ir.dialogue_blocks, & &1.id) ++
      Enum.map(ir.outline, & &1.id) ++
      title_ids
  end
end
