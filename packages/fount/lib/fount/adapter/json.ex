defmodule Fount.Adapter.JSON do
  @moduledoc """
  JSON projection of canonical screenplay structure.

  JSON is an interchange/query view, not Fount's internal model. The projection
  includes stable IDs, source coordinates, inline marks, structural views, and
  annotation provenance. Exact source bytes are opt-in.
  """

  alias Fount.Adapter.ExportResult

  @spec export(Fount.Document.t() | Fount.Screenplay.t(), keyword()) :: {:ok, ExportResult.t()}
  def export(doc, opts \\ [])

  def export(%Fount.Screenplay{} = model, opts) do
    if Keyword.get(opts, :projection, false), do: export_projection(model, opts), else: export_canonical(model, opts)
  end

  def export(doc, opts), do: export_projection(doc, opts)

  defp export_canonical(model, opts) do
    model = Fount.Screenplay.Model.refresh(model)

    artifact =
      if Keyword.get(opts, :include_source, false) and model.import do
        %{
          "format" => to_string(model.import.format),
          "bytes_base64" => Base.encode64(model.import.bytes),
          "sha256" => :crypto.hash(:sha256, model.import.bytes) |> Base.encode16(case: :lower),
          "render_hash" => model.import.render_hash,
          "revision_id" => model.import.revision_id,
          "losses" => model.import[:losses] || []
        }
      end

    payload = %{
      "schema" => "fount.screenplay.v2",
      "model" => Fount.Persistence.Codec.encode(model),
      "import_artifact" => artifact
    }

    {:ok,
     %ExportResult{
       data: Jason.encode!(payload, pretty: Keyword.get(opts, :pretty, true)),
       metadata: %{fidelity: "canonical_revision_snapshot", content_hash: model.revision.content_hash}
     }}
  end

  defp export_projection(doc, opts) do
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
      "cast" => doc |> Map.get(:cast, %{}) |> Map.values() |> Enum.sort_by(& &1.id) |> Enum.map(&struct_map/1),
      "mentions" => doc |> Map.get(:mentions, %{}) |> Map.values() |> Enum.sort_by(& &1.id) |> Enum.map(&struct_map/1),
      "annotations" => if(include_annotations?, do: annotations(doc), else: []),
      "source" => if(include_source?, do: source_bytes(doc), else: nil)
    }

    {:ok, %ExportResult{data: Jason.encode!(payload, pretty: Keyword.get(opts, :pretty, true))}}
  end

  @spec decode(binary()) :: {:ok, map()} | {:error, term()}
  def decode(json), do: Jason.decode(json)

  @doc "Imports a complete canonical snapshot; rejects malformed identity, hash and source-artifact data."
  def decode_model(json) do
    with {:ok, %{"schema" => "fount.screenplay.v2", "model" => data} = payload} <- Jason.decode(json),
         true <- Map.keys(payload) -- ~w(schema model import_artifact) == [] or {:error, :unknown_json_field},
         :ok <- validate_model_fields(data),
         :ok <- validate_nested_fields(data),
         model = Fount.Persistence.Codec.decode(data),
         [] <- Fount.Validate.screenplay(model),
         true <- data["revision"]["content_hash"] == model.revision.content_hash or {:error, :content_hash_mismatch},
         true <- data["revision"]["render_hash"] == model.revision.render_hash or {:error, :render_hash_mismatch},
         {:ok, artifact} <- decode_artifact(payload["import_artifact"]) do
      {:ok, %{model | import: artifact}}
    else
      {:error, _} = error -> error
      diagnostics when is_list(diagnostics) -> {:error, {:invalid_canonical_structure, diagnostics}}
      _ -> {:error, :canonical_json_v2_required}
    end
  rescue
    _ -> {:error, :invalid_canonical_json}
  end

  defp validate_model_fields(data) when is_map(data) do
    keys = ~w(id revision title elements scenes turns cast mentions authored_items annotations)
    lists = ~w(elements scenes turns cast mentions annotations)

    if Map.keys(data) -- keys == [] and keys -- Map.keys(data) == [] and
         Enum.all?(lists, &is_list(data[&1])) and is_map(data["revision"]) and is_map(data["authored_items"]) and
         match?({:ok, _}, Ecto.UUID.cast(data["id"])) and match?({:ok, _}, Ecto.UUID.cast(data["revision"]["id"])),
       do: :ok,
       else: {:error, :invalid_canonical_fields}
  end

  defp validate_model_fields(_), do: {:error, :invalid_canonical_fields}

  defp validate_nested_fields(data) do
    records = [
      {data["revision"], Fount.Revision},
      {data["elements"], Fount.IR.Element},
      {data["scenes"], Fount.IR.Scene},
      {data["turns"], Fount.IR.DialogueBlock},
      {data["cast"], Fount.Cast.Character},
      {data["mentions"], Fount.Cast.Mention},
      {data["annotations"], Fount.Annotation}
    ]

    nested =
      Enum.flat_map(data["elements"], fn e -> [e["source_span"], e["content_span"]] end) ++
        Enum.map(data["scenes"], & &1["source_span"]) ++
        Enum.map(data["turns"], & &1["source_span"])

    annotations =
      Enum.flat_map(data["annotations"], fn a ->
        [{a["target"], Fount.Annotation.Target}, {a["provenance"], Fount.Annotation.Provenance}]
      end)

    valid =
      Enum.all?(records ++ [{nested, Fount.Source.Span}] ++ annotations, fn
        {list, module} when is_list(list) -> Enum.all?(list, &known_fields?(&1, module))
        {value, module} -> known_fields?(value, module)
      end) and
        (is_nil(data["title"]) or
           (is_list(data["title"]) and
              Enum.all?(data["title"], &known_fields?(&1, Fount.IR.TitlePage.Entry)))) and
        Enum.all?(data["cast"], fn c ->
          is_list(c["aliases"]) and
            Enum.all?(c["aliases"], fn a ->
              is_map(a) and Map.keys(a) -- ~w(alias kind) == []
            end)
        end)

    if valid, do: :ok, else: {:error, :unknown_nested_canonical_field}
  end

  defp known_fields?(nil, _), do: true

  defp known_fields?(value, module) when is_map(value) do
    allowed = module.__struct__() |> Map.keys() |> List.delete(:__struct__) |> Enum.map(&to_string/1)
    Map.keys(value) -- allowed == []
  end

  defp known_fields?(_, _), do: false

  defp decode_artifact(nil), do: {:ok, nil}

  defp decode_artifact(%{"format" => format, "bytes_base64" => encoded, "sha256" => expected} = artifact)
       when format in ["fountain", "fdx"] do
    with true <-
           Map.keys(artifact) -- ~w(format bytes_base64 sha256 render_hash revision_id losses) == [] or
             {:error, :unknown_artifact_field},
         {:ok, bytes} <- Base.decode64(encoded),
         true <-
           :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) == expected or {:error, :artifact_hash_mismatch},
         {:ok, decoded} <- artifact_model(bytes, format),
         true <- decoded.revision.render_hash == artifact["render_hash"] or {:error, :artifact_render_identity_mismatch} do
      {:ok,
       %{
         format: if(format == "fountain", do: :fountain, else: :fdx),
         bytes: bytes,
         id: Fount.ID.v4(),
         revision_id: artifact["revision_id"],
         render_hash: artifact["render_hash"],
         losses: artifact["losses"] || []
       }}
    end
  end

  defp decode_artifact(_), do: {:error, :invalid_artifact}

  defp artifact_model(bytes, "fountain") do
    with {:ok, document} <- Fount.parse(bytes), do: {:ok, Fount.Screenplay.from_document(document)}
  end

  defp artifact_model(bytes, "fdx") do
    with {:ok, model, _} <- Fount.Screenplay.from_fdx(bytes), do: {:ok, model}
  end

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

  defp source_bytes(%Fount.Document{source: source}), do: source.raw

  defp source_bytes(%Fount.Screenplay{import: %{format: :fountain, bytes: bytes, revision_id: revision}} = doc)
       when revision == doc.revision.id,
       do: bytes

  defp source_bytes(%Fount.Screenplay{}), do: nil

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
  defp jsonify(value) when is_boolean(value), do: value
  defp jsonify(value) when is_atom(value), do: Atom.to_string(value)
  defp jsonify(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp jsonify(value) when is_list(value), do: Enum.map(value, &jsonify/1)
  defp jsonify(%_{} = value), do: value |> Map.from_struct() |> jsonify()
  defp jsonify(value) when is_map(value), do: Map.new(value, fn {key, item} -> {to_string(key), jsonify(item)} end)
  defp jsonify(value), do: inspect(value)
end
