defmodule Fount.Adapter.JSON do
  @moduledoc """
  JSON projection of canonical screenplay structure.

  JSON is an interchange/query view, not Fount's internal model. The projection
  includes stable IDs, source coordinates, inline marks, structural views, and
  annotation provenance. Exact source bytes are opt-in.
  """

  alias Fount.Adapter.ExportResult

  @spec export(Fount.Document.t(), keyword()) :: {:ok, ExportResult.t()}
  def export(doc, opts \\ []) do
    include_source? = Keyword.get(opts, :include_source, false)
    include_annotations? = Keyword.get(opts, :include_annotations, true)

    payload = %{
      "schema" => "fount.projection.v1",
      "document_id" => doc.id,
      "revision" => %{
        "id" => doc.revision.id,
        "parent_id" => doc.revision.parent_id,
        "created_at" => datetime(doc.revision.created_at),
        "actor" => doc.revision.actor,
        "message" => doc.revision.message
      },
      "title_page" => title_page(doc.ir.title_page),
      "elements" => Enum.map(doc.ir.elements, &element/1),
      "scenes" => Enum.map(doc.ir.scenes, &struct_map/1),
      "dialogue_blocks" => Enum.map(doc.ir.dialogue_blocks, &struct_map/1),
      "outline" => Enum.map(doc.ir.outline, &struct_map/1),
      "annotations" => if(include_annotations?, do: annotations(doc), else: []),
      "source" => if(include_source?, do: doc.source.raw, else: nil)
    }

    {:ok, %ExportResult{data: Jason.encode!(payload, pretty: Keyword.get(opts, :pretty, true))}}
  end

  @spec decode(binary()) :: {:ok, map()} | {:error, term()}
  def decode(json), do: Jason.decode(json)

  defp title_page(nil), do: []
  defp title_page(%{entries: entries}), do: Enum.map(entries, &struct_map/1)

  defp element(element) do
    %{
      "id" => element.id,
      "type" => Atom.to_string(element.type),
      "text" => element.text,
      "attrs" => jsonify(element.attrs || %{}),
      "inline" => Enum.map(element.inline || [], &struct_map/1),
      "source_span" => span(element.source_span),
      "content_span" => span(element.content_span),
      "origin" => to_string(element.origin || :unknown)
    }
  end

  defp annotations(doc) do
    doc.annotations
    |> Fount.Annotations.list()
    |> Enum.sort_by(& &1.id)
    |> Enum.map(fn annotation ->
      %{
        "id" => annotation.id,
        "namespace" => annotation.namespace,
        "kind" => to_string(annotation.kind),
        "target" => %{
          "node_id" => annotation.target.node_id,
          "span" => span(annotation.target.span)
        },
        "value" => jsonify(annotation.value),
        "confidence" => annotation.confidence,
        "dependencies" => annotation.dependencies || [],
        "provenance" => provenance(annotation.provenance)
      }
    end)
  end

  defp provenance(nil), do: nil

  defp provenance(value) do
    %{
      "producer" => value.producer,
      "producer_version" => value.producer_version,
      "model" => value.model,
      "source_revision" => value.source_revision,
      "created_at" => datetime(value.created_at),
      "metadata" => jsonify(value.metadata)
    }
  end

  defp struct_map(struct), do: struct |> Map.from_struct() |> jsonify()
  defp span(nil), do: nil
  defp span(value), do: value |> Map.from_struct() |> jsonify()
  defp datetime(nil), do: nil
  defp datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp jsonify(nil), do: nil
  defp jsonify(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp jsonify(value) when is_atom(value), do: Atom.to_string(value)
  defp jsonify(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp jsonify(value) when is_list(value), do: Enum.map(value, &jsonify/1)
  defp jsonify(%_{} = value), do: value |> Map.from_struct() |> jsonify()
  defp jsonify(value) when is_map(value), do: Map.new(value, fn {key, item} -> {to_string(key), jsonify(item)} end)
  defp jsonify(value), do: inspect(value)
end
