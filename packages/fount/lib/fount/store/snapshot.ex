defmodule Fount.Store.Snapshot do
  @moduledoc "Portable sidecar payload: identities, annotations, and revision metadata only."

  alias Fount.Annotation
  alias Fount.Annotation.{Provenance, Target}
  alias Fount.Source.Span

  @schema_version 1

  @spec dump(Fount.Document.t()) :: map()
  def dump(doc) do
    %{
      "schema_version" => @schema_version,
      "document_id" => doc.id,
      "revision" => %{
        "id" => doc.revision.id,
        "parent_id" => doc.revision.parent_id,
        "created_at" => encode_datetime(doc.revision.created_at),
        "actor" => doc.revision.actor,
        "message" => doc.revision.message
      },
      "identity_anchors" => Fount.Identity.anchors(doc.ir),
      "annotations" => Enum.map(Fount.Annotations.list(doc.annotations), &encode_annotation/1)
    }
  end

  @spec encode!(Fount.Document.t()) :: binary()
  def encode!(doc), do: doc |> dump() |> Jason.encode!(pretty: true)

  @spec decode(binary()) :: {:ok, map()} | {:error, term()}
  def decode(json), do: Jason.decode(json)

  @spec parse_options(map()) :: keyword()
  def parse_options(snapshot) do
    revision = snapshot["revision"] || %{}

    [
      document_id: snapshot["document_id"],
      identity_anchors: snapshot["identity_anchors"] || [],
      annotations: decode_annotations(snapshot["annotations"] || []),
      parent_revision_id: revision["parent_id"],
      actor: revision["actor"],
      message: revision["message"],
      revision_created_at: decode_datetime(revision["created_at"])
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp encode_annotation(%Annotation{} = annotation) do
    %{
      "id" => annotation.id,
      "namespace" => annotation.namespace,
      "kind" => to_string(annotation.kind),
      "target" => %{
        "node_id" => annotation.target.node_id,
        "span" => encode_span(annotation.target.span)
      },
      "value" => jsonify(annotation.value),
      "provenance" => encode_provenance(annotation.provenance),
      "confidence" => annotation.confidence,
      "dependencies" => annotation.dependencies || []
    }
  end

  defp decode_annotations(values) do
    Enum.reduce(values, Fount.Annotations.new(), fn value, set ->
      target = value["target"] || %{}

      annotation = %Annotation{
        id: value["id"],
        namespace: value["namespace"],
        kind: value["kind"],
        target: %Target{node_id: target["node_id"], span: decode_span(target["span"])},
        value: value["value"],
        provenance: decode_provenance(value["provenance"] || %{}),
        confidence: value["confidence"],
        dependencies: value["dependencies"] || []
      }

      Fount.Annotations.put(set, annotation)
    end)
  end

  defp encode_provenance(%Provenance{} = p) do
    %{
      "producer" => p.producer,
      "producer_version" => p.producer_version,
      "model" => p.model,
      "source_revision" => p.source_revision,
      "created_at" => encode_datetime(p.created_at),
      "metadata" => jsonify(p.metadata)
    }
  end

  defp decode_provenance(map) do
    %Provenance{
      producer: map["producer"] || "unknown",
      producer_version: map["producer_version"],
      model: map["model"],
      source_revision: map["source_revision"],
      created_at: decode_datetime(map["created_at"]),
      metadata: map["metadata"]
    }
  end

  defp encode_span(nil), do: nil

  defp encode_span(%Span{} = span) do
    %{
      "byte_start" => span.byte_start,
      "byte_end" => span.byte_end,
      "line_start" => span.line_start,
      "column_start" => span.column_start,
      "line_end" => span.line_end,
      "column_end" => span.column_end
    }
  end

  defp decode_span(nil), do: nil

  defp decode_span(map) do
    %Span{
      byte_start: map["byte_start"],
      byte_end: map["byte_end"],
      line_start: map["line_start"],
      column_start: map["column_start"],
      line_end: map["line_end"],
      column_end: map["column_end"]
    }
  end

  defp encode_datetime(nil), do: nil
  defp encode_datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp decode_datetime(nil), do: nil

  defp decode_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp jsonify(nil), do: nil
  defp jsonify(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp jsonify(%Span{} = value), do: encode_span(value)
  defp jsonify(value) when is_atom(value), do: Atom.to_string(value)
  defp jsonify(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp jsonify(value) when is_list(value), do: Enum.map(value, &jsonify/1)

  defp jsonify(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {to_string(key), jsonify(item)} end)
  end

  defp jsonify(value), do: inspect(value)
end
