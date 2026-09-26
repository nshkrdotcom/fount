defmodule Fount.Persistence.Codec do
  @moduledoc false
  alias Fount.Annotation
  alias Fount.Annotation.Provenance
  alias Fount.Annotation.Target
  alias Fount.Cast.Character
  alias Fount.Cast.Mention
  alias Fount.IR.DialogueBlock
  alias Fount.IR.Element
  alias Fount.IR.Scene
  alias Fount.IR.Script
  alias Fount.IR.TitlePage
  alias Fount.Revision
  alias Fount.Screenplay
  alias Fount.Screenplay.Model

  @element_types Map.new(
                   ~w(scene_heading action character dialogue parenthetical transition centered lyric section synopsis page_break note boneyard blank unknown),
                   fn name -> {name, String.to_atom(name)} end
                 )
  @mention_roles Map.new(~w(speaker_cue action dialogue_reference parenthetical), fn name ->
                   {name, String.to_atom(name)}
                 end)
  @mention_statuses Map.new(~w(confirmed suggested ambiguous), fn name ->
                      {name, String.to_atom(name)}
                    end)
  @atom_attrs Map.new(
                ~w(forced? number extension dual? level intentional_blank? dual_with_cue dual_side),
                fn name -> {name, String.to_atom(name)} end
              )
  @codec_keys [
                Revision,
                Element,
                Scene,
                DialogueBlock,
                Character,
                Mention,
                Annotation,
                Target,
                Provenance,
                Fount.Source.Span,
                TitlePage.Entry
              ]
              |> Enum.flat_map(fn module -> module |> struct() |> Map.keys() end)
              |> Enum.reject(&(&1 == :__struct__))
              |> Enum.uniq()
              |> Map.new(&{Atom.to_string(&1), &1})

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
      "authored_items" => plain(screenplay.authored_items),
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
        aliases = Enum.map(value[:aliases] || [], &%{alias: &1["alias"], kind: &1["kind"]})
        character = struct(Character, %{value | aliases: aliases})
        {character.id, character}
      end)

    mentions =
      Map.new(data["mentions"], fn value ->
        value = keys(value)

        value = %{
          value
          | role: Map.fetch!(@mention_roles, value.role),
            status: Map.fetch!(@mention_statuses, value.status)
        }

        mention = struct(Mention, value)
        {mention.id, mention}
      end)

    annotations =
      Map.new(data["annotations"] || [], fn value ->
        annotation = decode_annotation(value)
        {annotation.id, annotation}
      end)

    %Screenplay{
      id: data["id"],
      revision: revision,
      ir: ir,
      cast: cast,
      mentions: mentions,
      annotations: annotations,
      authored_items: data["authored_items"] || %{}
    }
    |> Model.refresh()
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
      | type: Map.fetch!(@element_types, value.type),
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
    struct(DialogueBlock, %{value | source_span: decode_span(value[:source_span]), side: side(value[:side])})
  end

  defp side("left"), do: :left
  defp side("right"), do: :right
  defp side(nil), do: nil

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

  defp keys(map), do: Map.new(map, fn {key, value} -> {Map.fetch!(@codec_keys, key), value} end)

  defp attr_keys(map) do
    Map.new(map, fn {key, value} ->
      {Map.get(@atom_attrs, key, key), value}
    end)
  end
end
