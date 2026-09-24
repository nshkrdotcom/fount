defmodule Fount.Fountain.CST do
  @moduledoc """
  Concrete syntax tree preserving every source byte.

  Nodes form an ordered, non-overlapping partition of the Fountain source. Title
  page bytes that are not part of a semantic title entry are represented as
  `:title_trivia` nodes rather than discarded.
  """

  defmodule Node do
    @moduledoc false
    @enforce_keys [:id, :type, :span, :content_span, :raw, :text]
    defstruct [:id, :type, :span, :content_span, :raw, :text, :attrs, :inline, :line_start, :line_end]
    @type t :: %__MODULE__{}
  end

  @enforce_keys [:nodes]
  defstruct [:nodes, :title_page]
  @type t :: %__MODULE__{nodes: [Node.t()], title_page: Fount.IR.TitlePage.t() | nil}

  @spec render(t()) :: binary()
  def render(%__MODULE__{nodes: nodes}) do
    nodes |> Enum.map(& &1.raw) |> IO.iodata_to_binary()
  end

  @spec exact?(t(), Fount.Source.t()) :: boolean()
  def exact?(%__MODULE__{} = cst, %Fount.Source{} = source), do: render(cst) == source.raw

  @doc "Apply a semantic identity reconciliation map to the CST as well as title-page references."
  @spec remap_ids(t(), map(), String.t()) :: t()
  def remap_ids(%__MODULE__{} = cst, id_map, document_id) do
    title_page = remap_title_page(cst.title_page, id_map)

    nodes =
      Enum.map(cst.nodes, fn
        %Node{type: :title_page} = node ->
          original_entry_id = get_in(node.attrs || %{}, [:entry_id])
          entry_id = Map.get(id_map, original_entry_id, original_entry_id) || node.id
          attrs = Map.put(node.attrs || %{}, :entry_id, entry_id)
          %{node | id: Fount.ID.v5(document_id, ["title-node:", entry_id]), attrs: attrs}

        %Node{} = node ->
          %{node | id: Map.get(id_map, node.id, node.id)}
      end)

    %{cst | nodes: nodes, title_page: title_page}
  end

  defp remap_title_page(nil, _id_map), do: nil

  defp remap_title_page(%Fount.IR.TitlePage{} = page, id_map) do
    entries =
      Enum.map(page.entries, fn entry ->
        %{entry | id: Map.get(id_map, entry.id, entry.id)}
      end)

    %{page | entries: entries}
  end
end
