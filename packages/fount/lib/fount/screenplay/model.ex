defmodule Fount.Screenplay.Model do
  @moduledoc false
  alias Fount.{ID, Index}
  alias Fount.Cast.{Character, Mention}
  alias Fount.Writing.CanonicalJSON

  def refresh(model) do
    old_scenes = Map.new(model.ir.scenes || [], &{&1.heading_id, &1})
    old_blocks = Map.new(model.ir.dialogue_blocks || [], &{&1.cue_id, &1})
    rebuilt = Fount.IR.rebuild_views(model.ir)
    scene_ids = Map.new(rebuilt.scenes, fn scene -> {scene.id, Map.get(old_scenes, scene.heading_id, scene).id} end)

    block_ids =
      Map.new(rebuilt.dialogue_blocks, fn block -> {block.id, Map.get(old_blocks, block.cue_id, block).id} end)

    scenes =
      Enum.map(rebuilt.scenes, fn scene ->
        prior = Map.get(old_scenes, scene.heading_id, scene)
        %{scene | id: prior.id, omitted?: prior.omitted?}
      end)

    blocks =
      Enum.map(rebuilt.dialogue_blocks, fn block ->
        %{block | id: block_ids[block.id], dual_with: block_ids[block.dual_with]}
      end)

    outline = Enum.map(rebuilt.outline, &%{&1 | scene_ids: Enum.map(&1.scene_ids, fn id -> scene_ids[id] end)})
    ir = %{rebuilt | scenes: scenes, dialogue_blocks: blocks, outline: outline}
    model = %{model | ir: ir, index: Index.build(ir)}

    mentions =
      Map.reject(model.mentions, fn {_, mention} ->
        element = model.index.by_id[mention.element_id]

        is_nil(element) or
          Fount.Writing.UTF8Span.verify(element.text, {mention.byte_start, mention.byte_end}, mention.surface) != :ok
      end)

    mentions = Map.new(mentions, fn {id, item} -> {id, %{item | model_revision_id: model.revision.id}} end)
    model = %{model | mentions: mentions}

    items =
      Map.new(model.authored_items, fn {id, item} ->
        item =
          if match?({:error, _}, Fount.Target.resolve(model, item["target"])),
            do: Map.put(item, "status", "unresolved"),
            else: item

        {id, item}
      end)

    model = %{model | authored_items: items}

    revision = %{
      model.revision
      | content_hash: CanonicalJSON.hash(content(model)),
        render_hash: CanonicalJSON.hash(render_content(model))
    }

    %{model | revision: revision}
  end

  def resolve_cast(model, :manual), do: model

  def resolve_cast(model, :literal_cues) do
    Enum.reduce(Enum.filter(model.ir.elements, &(&1.type == :character)), model, fn cue, model ->
      name = cue.text |> String.replace(~r/\s*\([^)]*\)\s*$/, "") |> String.trim() |> String.upcase()
      id = ID.v5(model.id, ["cast:", name])
      character = Map.get(model.cast, id, %Character{id: id, display_name: name})

      mention = %Mention{
        id: ID.v5(model.id, ["cue:", cue.id]),
        element_id: cue.id,
        character_id: id,
        role: :speaker_cue,
        status: :confirmed,
        surface: cue.text,
        byte_start: 0,
        byte_end: byte_size(cue.text),
        model_revision_id: model.revision.id,
        producer: "writer.import",
        confidence: 1.0
      }

      %{model | cast: Map.put(model.cast, id, character), mentions: Map.put(model.mentions, mention.id, mention)}
    end)
  end

  def content(model) do
    %{
      "id" => model.id,
      "elements" => Enum.map(model.ir.elements, &Map.take(&1, [:id, :type, :text, :inline, :attrs])),
      "scenes" => Enum.map(model.ir.scenes, &Map.take(&1, [:id, :heading_id, :element_ids, :number, :omitted?])),
      "blocks" => Enum.map(model.ir.dialogue_blocks, &Map.take(&1, [:id, :cue_id, :body_ids, :dual_with, :side])),
      "title" => title(model),
      "cast" => sorted(model.cast),
      "mentions" => model.mentions |> sorted() |> Enum.map(&Map.drop(&1, [:model_revision_id, :producer, :confidence])),
      "authored_items" =>
        model.authored_items
        |> sorted()
        |> Enum.map(fn item ->
          item |> Map.delete("provenance") |> Map.update("value", %{}, &Map.drop(&1, ["resolution"]))
        end)
    }
    |> plain()
  end

  def render_content(model) do
    %{
      "elements" =>
        Enum.map(model.ir.elements, fn e ->
          %{
            type: e.type,
            text: e.text,
            inline: e.inline,
            attrs: Map.take(e.attrs || %{}, [:forced?, :level, :number, :dual?, :dual_side, "dual_side"])
          }
        end),
      "title" => Enum.map(title(model), &Map.drop(&1, [:id, :raw, :span])),
      "scenes" => Enum.map(model.ir.scenes, &Map.take(&1, [:number, :omitted?]))
    }
    |> plain()
  end

  def plain(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def plain(%_{} = value), do: value |> Map.from_struct() |> plain()
  def plain(value) when is_map(value), do: Map.new(value, fn {k, v} -> {to_string(k), plain(v)} end)
  def plain(value) when is_list(value), do: Enum.map(value, &plain/1)
  def plain(value) when is_tuple(value), do: value |> Tuple.to_list() |> plain()
  def plain(value) when is_boolean(value) or is_nil(value), do: value
  def plain(value) when is_atom(value), do: Atom.to_string(value)
  def plain(value), do: value
  defp sorted(values), do: values |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))
  defp title(%{ir: %{title_page: nil}}), do: []
  defp title(model), do: model.ir.title_page.entries
end
