defmodule Fount.Persistence.Codec do
  @moduledoc false

  alias Fount.Annotation
  alias Fount.Annotation.{Provenance, Target}
  alias Fount.Cast.{Character, Mention}
  alias Fount.IR.{DialogueBlock, Element, Scene, Script, TitlePage}
  alias Fount.{Revision, Screenplay}

  @spec encode(Screenplay.t()) :: map()
  def encode(screenplay) do
    %{
      "id" => screenplay.id,
      "revision" => plain(screenplay.revision),
      "title" => title(screenplay.ir.title_page),
      "elements" => Enum.map(screenplay.ir.elements, &plain/1),
      "scenes" => Enum.map(screenplay.ir.scenes, &plain/1),
      "turns" => Enum.map(screenplay.ir.dialogue_blocks, &plain/1),
      "cast" => Enum.map(Map.values(screenplay.cast), &plain/1),
      "mentions" => Enum.map(Map.values(screenplay.mentions), &plain/1),
      "annotations" => Enum.map(Map.values(screenplay.annotations || %{}), &plain/1)
    }
  end

  @spec decode(map()) :: Screenplay.t()
  def decode(data) do
    revision =
      data["revision"]
      |> keys()
      |> Map.update(:created_at, nil, &decode_datetime/1)
      |> then(&struct(Revision, &1))

    ir =
      %Script{
        document_id: data["id"],
        title_page: decode_title(data["title"]),
        elements: Enum.map(data["elements"], &decode_element/1),
        scenes: Enum.map(data["scenes"], &decode_scene/1),
        dialogue_blocks: Enum.map(data["turns"], &decode_turn/1),
        outline: [],
        metadata: %{}
      }
      |> Fount.IR.restore_views()

    cast =
      Map.new(data["cast"], fn value ->
        value = keys(value)
        aliases = Enum.map(value[:aliases] || [], &%{alias: &1["alias"], kind: String.to_existing_atom(&1["kind"])})
        character = struct(Character, %{value | aliases: aliases})
        {character.id, character}
      end)

    mentions =
      Map.new(data["mentions"], fn value ->
        value = keys(value)
        value = %{value | role: String.to_existing_atom(value.role), status: String.to_existing_atom(value.status)}
        mention = struct(Mention, value)
        {mention.id, mention}
      end)

    annotations =
      Map.new(data["annotations"] || [], fn value ->
        annotation = decode_annotation(value)
        {annotation.id, annotation}
      end)

    %Screenplay{id: data["id"], revision: revision, ir: ir, cast: cast, mentions: mentions, annotations: annotations}
  end

  defp decode_annotation(value) do
    fields = keys(value)
    target = struct(Target, keys(fields.target))

    provenance =
      fields.provenance
      |> keys()
      |> Map.update(:created_at, nil, &decode_datetime/1)
      |> then(&struct(Provenance, &1))

    struct(Annotation, %{fields | target: target, provenance: provenance})
  end

  defp decode_element(value) do
    value = keys(value)

    value = %{
      value
      | type: String.to_existing_atom(value.type),
        attrs: attr_keys(value[:attrs] || %{}),
        source_span: decode_span(value[:source_span]),
        content_span: decode_span(value[:content_span])
    }

    struct(Element, value)
  end

  defp decode_scene(value) do
    value = keys(value)
    struct(Scene, %{value | source_span: decode_span(value[:source_span])})
  end

  defp decode_turn(value) do
    value = keys(value)
    struct(DialogueBlock, %{value | source_span: decode_span(value[:source_span])})
  end

  defp decode_span(nil), do: nil
  defp decode_span(value), do: struct(Fount.Source.Span, keys(value))

  defp decode_title(nil), do: nil
  defp decode_title(entries), do: %TitlePage{entries: Enum.map(entries, &struct(TitlePage.Entry, keys(&1)))}

  defp decode_datetime(nil), do: nil

  defp decode_datetime(text) do
    case DateTime.from_iso8601(text) do
      {:ok, value, _} -> value
      _ -> nil
    end
  end

  defp title(nil), do: nil
  defp title(%TitlePage{entries: entries}), do: Enum.map(entries, &plain/1)

  defp plain(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp plain(nil), do: nil
  defp plain(value) when is_boolean(value), do: value
  defp plain(%_{} = value), do: value |> Map.from_struct() |> plain()
  defp plain(value) when is_map(value), do: Map.new(value, fn {key, item} -> {to_string(key), plain(item)} end)
  defp plain(value) when is_list(value), do: Enum.map(value, &plain/1)
  defp plain(value) when is_atom(value), do: Atom.to_string(value)
  defp plain(value), do: value

  defp keys(map), do: Map.new(map, fn {key, value} -> {String.to_existing_atom(key), value} end)

  defp attr_keys(map) do
    Map.new(map, fn {key, value} ->
      if key in ["forced?", "number", "extension", "dual?", "level", "intentional_blank?"],
        do: {String.to_existing_atom(key), value},
        else: {key, value}
    end)
  end
end
