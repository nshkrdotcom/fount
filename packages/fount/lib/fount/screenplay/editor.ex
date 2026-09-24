defmodule Fount.Screenplay.Editor do
  @moduledoc false
  alias Fount.{ID, Query, Screenplay}
  alias Fount.Screenplay.Model
  alias Fount.IR.{Element, Scene, TitlePage}
  alias Fount.Writing.{LocalReferences, UTF8Span}

  @types ~w(action character dialogue parenthetical transition centered lyric section synopsis page_break note boneyard blank)

  def apply(base, operations, opts) when is_list(operations) do
    try do
      normalized = Enum.map(operations, &normalize/1)
      {:ok, compiled, mapping} = unwrap(LocalReferences.compile(normalized, opts))
      allowed_new = MapSet.new(Map.values(mapping))
      context = %{new: allowed_new, restore: Keyword.get(opts, :restore_registry, %{})}

      updated =
        Enum.reduce(compiled, Model.refresh(base), fn op, model -> step(model, op, context) |> Model.refresh() end)

      diagnostics = Fount.Validate.screenplay(updated)
      if diagnostics != [], do: fail({:invalid_model, diagnostics})
      changed = Model.content(updated) != Model.content(base)

      model =
        if changed do
          revision = %Fount.Revision{
            id: ID.v4(),
            parent_id: base.revision.id,
            created_at: DateTime.utc_now(),
            actor: Keyword.get(opts, :actor)
          }

          %{updated | revision: revision} |> Model.refresh()
        else
          base
        end

      impact = Fount.ChangeImpact.between(base, model)

      annotations =
        Map.reject(model.annotations, fn {_, a} ->
          id = a.target.node_id

          (is_nil(Query.node(model, id)) and is_nil(Query.scene(model, id)) and id != model.id) or
            (a.provenance.producer != "writer" and Enum.any?(impact.changed_targets, &(&1.id == id)))
        end)

      model = %{model | annotations: annotations}

      changes =
        Map.merge(impact, %{
          base_revision: base.revision.id,
          result_revision: model.revision.id,
          operations: compiled,
          local_references: mapping,
          lineage: lineage(base, model),
          origin_by_group: %{},
          diagnostics: []
        })

      {:ok, model, changes}
    rescue
      e in [KeyError, ArgumentError, MatchError, BadMapError, FunctionClauseError] ->
        {:error, {:invalid_operation, Exception.message(e)}}
    catch
      {:edit_error, reason} -> {:error, reason}
    end
  end

  def apply(_, _, _), do: {:error, :operations_must_be_a_list}

  defp normalize(%Fount.Edit.Op{kind: :set_character_cue, target: id, value: text}),
    do: %{"kind" => "set_character_cue", "target" => target("element", id), "value" => text}

  defp normalize(%Fount.Edit.Op{kind: :insert_scene_after, target: id, value: value}) do
    %{
      "kind" => "insert_scene",
      "value" => %{
        "after_scene_id" => id,
        "scene" => %{
          "local_id" => "new:scene-#{ID.v4()}",
          "heading" => value.heading,
          "elements" =>
            Enum.map(value.content, fn item ->
              %{
                "local_id" => "new:el-#{ID.v4()}",
                "type" => to_string(item.type),
                "text" => item.text,
                "attrs" => Model.plain(Map.get(item, :attrs, %{}))
              }
            end)
        }
      }
    }
  end

  defp normalize(%Fount.Edit.Op{kind: kind, target: id, value: value}) do
    type = if kind == :replace_text, do: "element", else: "scene"
    value = if kind == :move_scene, do: %{"after_scene_id" => value}, else: value
    op = %{"kind" => to_string(kind), "target" => target(type, id)}
    if kind == :delete_scene, do: op, else: Map.put(op, "value", value)
  end

  defp normalize(%{"kind" => _} = op), do: op
  defp normalize(_), do: fail(:invalid_operation)

  defp step(model, %{"kind" => kind, "target" => target, "value" => text}, _)
       when kind in ["replace_text", "set_character_cue"] and is_binary(text) do
    element = resolve!(model, target, :element)

    if kind == "replace_text" and
         element.type not in [:action, :dialogue, :parenthetical, :lyric, :note, :centered, :transition],
       do: fail(:invalid_text_target)

    if kind == "set_character_cue" and element.type != :character, do: fail(:not_a_character_cue)

    text =
      case target["span"] do
        nil ->
          text

        %{"byte_start" => first, "byte_end" => last} ->
          unwrap(UTF8Span.extract(element.text, {first, last}))
          binary_part(element.text, 0, first) <> text <> binary_part(element.text, last, byte_size(element.text) - last)
      end

    model = update_element(model, element.id, text)

    model =
      if kind == "set_character_cue",
        do: update_attrs(model, element.id, %{forced?: text != String.upcase(text)}),
        else: model

    if kind == "set_character_cue", do: refresh_cue_mentions(model, element.id, text), else: model
  end

  defp step(model, %{"kind" => "set_scene_heading", "target" => target, "value" => text}, _) when is_binary(text) do
    scene = resolve!(model, target, :scene)

    model
    |> update_element(scene.heading_id, text)
    |> update_attrs(scene.heading_id, %{forced?: not Fount.SceneHeading.standard_fountain?(text)})
  end

  defp step(model, %{"kind" => "set_scene_number", "target" => target, "value" => number}, _)
       when is_binary(number) or is_nil(number) do
    scene = resolve!(model, target, :scene)
    model |> update_attrs(scene.heading_id, %{number: number})
  end

  defp step(model, %{"kind" => "omit_scene", "target" => target, "value" => value}, _) when is_boolean(value) do
    scene = resolve!(model, target, :scene)

    %{
      model
      | ir: %{
          model.ir
          | scenes: Enum.map(model.ir.scenes, fn s -> if s.id == scene.id, do: %{s | omitted?: value}, else: s end)
        }
    }
  end

  defp step(model, %{"kind" => "delete_scene", "target" => target}, context) do
    scene = resolve!(model, target, :scene)
    step(model, %{"kind" => "replace_sequence", "value" => %{"scene_ids" => [scene.id], "scenes" => []}}, context)
  end

  defp step(model, %{"kind" => "move_scene", "target" => target, "value" => %{"after_scene_id" => after_id}}, _) do
    scene = resolve!(model, target, :scene)
    if scene.id == after_id, do: fail(:move_after_self)
    if after_id && !Query.scene(model, after_id), do: fail(:unknown_destination)
    moving = MapSet.new(scene.element_ids)
    content = Enum.filter(model.ir.elements, &MapSet.member?(moving, &1.id))
    remaining = Enum.reject(model.ir.elements, &MapSet.member?(moving, &1.id))
    index = insert_index(model, remaining, after_id)
    %{model | ir: %{model.ir | elements: insert(remaining, index, content)}}
  end

  defp step(model, %{"kind" => "insert_scene", "value" => %{"after_scene_id" => after_id, "scene" => spec}}, context) do
    if after_id && !Query.scene(model, after_id), do: fail(:unknown_destination)
    {scene, elements} = scene_spec(model, spec, MapSet.new(), context)
    index = insert_index(model, model.ir.elements, after_id)

    %{
      model
      | ir: %{model.ir | elements: insert(model.ir.elements, index, elements), scenes: model.ir.scenes ++ [scene]}
    }
  end

  defp step(model, %{"kind" => "replace_sequence", "value" => %{"scene_ids" => ids, "scenes" => specs}}, context)
       when is_list(ids) and ids != [] and is_list(specs) do
    scenes = Enum.map(ids, fn id -> Query.scene(model, id) || fail({:unknown_scene, id}) end)
    positions = Enum.map(scenes, fn s -> Enum.find_index(model.ir.scenes, &(&1.id == s.id)) end)

    if positions != Enum.to_list(hd(positions)..List.last(positions)) or length(Enum.uniq(ids)) != length(ids),
      do: fail(:noncontiguous_sequence)

    available = MapSet.new(Enum.flat_map(scenes, & &1.element_ids) ++ ids)
    pairs = Enum.map(specs, &scene_spec(model, &1, available, context))
    replacements = Enum.flat_map(pairs, &elem(&1, 1))
    first = Enum.find_index(model.ir.elements, &(&1.id == hd(scenes).heading_id))
    remaining = Enum.reject(model.ir.elements, &MapSet.member?(available, &1.id))
    kept_scenes = Enum.reject(model.ir.scenes, &(&1.id in ids))

    %{
      model
      | ir: %{
          model.ir
          | elements: insert(remaining, first, replacements),
            scenes: kept_scenes ++ Enum.map(pairs, &elem(&1, 0))
        }
    }
  end

  defp step(model, %{"kind" => "replace_scene_body", "target" => target, "value" => %{"elements" => specs}}, context) do
    scene = resolve!(model, target, :scene)
    heading = Query.node(model, scene.heading_id)

    step(
      model,
      %{
        "kind" => "replace_sequence",
        "value" => %{
          "scene_ids" => [scene.id],
          "scenes" => [
            %{
              "id" => scene.id,
              "heading" => heading.text,
              "number" => scene.number,
              "omitted" => scene.omitted?,
              "elements" => specs
            }
          ]
        }
      },
      context
    )
  end

  defp step(model, %{"kind" => "insert_elements", "target" => target, "value" => value}, context) do
    owner = resolve!(model, target, [:scene, :screenplay])

    scope =
      if target["kind"] == "scene",
        do: tl(owner.element_ids),
        else: Enum.filter(model.ir.elements, &is_nil(Query.scene_for(model, &1.id))) |> Enum.map(& &1.id)

    anchor = value["anchor_id"]
    position = value["position"]
    if position in ["before", "after"] and anchor not in scope, do: fail(:invalid_anchor)

    index =
      case position do
        "before" ->
          Enum.find_index(model.ir.elements, &(&1.id == anchor))

        "after" ->
          Enum.find_index(model.ir.elements, &(&1.id == anchor)) + 1

        "start" ->
          if target["kind"] == "scene",
            do: Enum.find_index(model.ir.elements, &(&1.id == owner.heading_id)) + 1,
            else: 0

        "end" ->
          if scope == [],
            do:
              if(target["kind"] == "scene",
                do: Enum.find_index(model.ir.elements, &(&1.id == owner.heading_id)) + 1,
                else: 0
              ),
            else: Enum.find_index(model.ir.elements, &(&1.id == List.last(scope))) + 1

        _ ->
          fail(:invalid_position)
      end

    elements = Enum.map(value["elements"], &element_spec(model, &1, MapSet.new(), context))
    %{model | ir: %{model.ir | elements: insert(model.ir.elements, index, elements)}}
  end

  defp step(model, %{"kind" => "delete_elements", "value" => %{"ids" => ids}}, _) when is_list(ids) do
    Enum.each(ids, fn id ->
      element = Query.node(model, id) || fail({:unknown_element, id})
      if element.type == :scene_heading, do: fail(:use_delete_scene)
    end)

    %{model | ir: %{model.ir | elements: Enum.reject(model.ir.elements, &(&1.id in ids))}}
  end

  defp step(model, %{"kind" => "put_character", "value" => value}, context) do
    ensure_id(value["id"], MapSet.new(Map.keys(model.cast)), context)
    aliases = Enum.map(value["aliases"] || [], fn a -> %{alias: a["alias"], kind: a["kind"]} end)

    c = %Fount.Cast.Character{
      id: value["id"],
      display_name: value["display_name"],
      notes: value["notes"],
      aliases: aliases,
      attributes: value["attributes"] || %{}
    }

    if !is_binary(c.display_name) or c.display_name == "", do: fail(:invalid_character)
    %{model | cast: Map.put(model.cast, c.id, c)}
  end

  defp step(model, %{"kind" => "link_speaker", "target" => target, "value" => %{"character_id" => id}}, _) do
    block = resolve!(model, target, :dialogue_block)
    if !model.cast[id], do: fail(:unknown_character)
    {:ok, linked} = Screenplay.link_cue(model, block.cue_id, id)
    %{linked | revision: model.revision}
  end

  defp step(model, %{"kind" => "rename_character", "target" => target, "value" => value}, _) do
    c = resolve!(model, target, :character)
    name = value["name"]
    if !is_binary(name) or name == "", do: fail(:invalid_character_name)
    chosen = value["mention_ids"] || []

    mentions =
      model.mentions
      |> Map.values()
      |> Enum.filter(
        &(&1.character_id == c.id and &1.status == :confirmed and (&1.role == :speaker_cue or &1.id in chosen))
      )

    if Enum.any?(chosen, fn id -> not Enum.any?(mentions, &(&1.id == id)) end), do: fail(:unconfirmed_mention)

    model =
      Enum.reduce(Enum.sort_by(mentions, &{-&1.byte_start}), model, fn m, acc ->
        element = Query.node(acc, m.element_id)
        suffix = if m.role == :speaker_cue, do: (Regex.run(~r/\s+\([^)]*\)$/, element.text) || [""]) |> hd(), else: ""

        text =
          binary_part(element.text, 0, m.byte_start) <>
            name <> suffix <> binary_part(element.text, m.byte_end, byte_size(element.text) - m.byte_end)

        acc = update_element(acc, element.id, text)
        updated = %{m | surface: name <> suffix, byte_end: m.byte_start + byte_size(name <> suffix)}
        %{acc | mentions: Map.put(acc.mentions, m.id, updated)}
      end)

    %{model | cast: Map.put(model.cast, c.id, %{c | display_name: name})}
  end

  defp step(model, %{"kind" => "put_authored_item", "value" => value}, context) do
    ensure_id(value["id"], MapSet.new(Map.keys(model.authored_items)), context)

    if value["kind"] not in ~w(brief story_plan note constraint fact voice_direction sequence storyline story_time perspective_access),
      do: fail(:invalid_authored_kind)

    if value["status"] not in ~w(active unresolved resolved) or not is_map(value["value"]),
      do: fail(:invalid_authored_item)

    if value["status"] != "unresolved", do: unwrap(Fount.Target.resolve(model, value["target"]))
    %{model | authored_items: Map.put(model.authored_items, value["id"], value)}
  end

  defp step(model, %{"kind" => "delete_authored_item", "target" => target}, _) do
    item = resolve!(model, target, :authored_item)
    %{model | authored_items: Map.delete(model.authored_items, item["id"])}
  end

  defp step(model, %{"kind" => "set_title", "value" => entries}, context) when is_list(entries) do
    available = MapSet.new(Enum.map((model.ir.title_page && model.ir.title_page.entries) || [], & &1.id))

    entries =
      Enum.map(entries, fn e ->
        ensure_id(e["id"], available, context)
        %TitlePage.Entry{id: e["id"], key: e["key"], values: e["values"]}
      end)

    %{model | ir: %{model.ir | title_page: %TitlePage{entries: entries}}}
  end

  defp step(_, op, _), do: fail({:invalid_operation, op["kind"]})

  defp scene_spec(model, spec, available, context) do
    id = spec["id"]
    ensure_id(id, available, context)
    old = Query.scene(model, id)

    heading = %Element{
      id: (old && old.heading_id) || ID.v4(),
      type: :scene_heading,
      text: spec["heading"],
      attrs: %{number: spec["number"], forced?: not Fount.SceneHeading.standard_fountain?(spec["heading"])}
    }

    body = Enum.map(spec["elements"], &element_spec(model, &1, available, context))

    scene = %Scene{
      id: id,
      heading_id: heading.id,
      element_ids: Enum.map([heading | body], & &1.id),
      number: spec["number"],
      omitted?: Map.get(spec, "omitted", false)
    }

    {scene, [heading | body]}
  end

  defp element_spec(model, %{"keep" => id}, available, context) do
    ensure_id(id, available, %{context | new: MapSet.new()})
    Query.node(model, id) || Map.get(context.restore, id) || fail(:unknown_keep)
  end

  defp element_spec(model, spec, available, context) do
    id = spec["id"]
    ensure_id(id, available, context)

    if spec["type"] not in @types or !is_binary(spec["text"]) or !String.valid?(spec["text"]),
      do: fail(:invalid_element)

    old = Query.node(model, id)

    type =
      Enum.find(
        [
          :action,
          :character,
          :dialogue,
          :parenthetical,
          :transition,
          :centered,
          :lyric,
          :section,
          :synopsis,
          :page_break,
          :note,
          :boneyard,
          :blank
        ],
        &(to_string(&1) == spec["type"])
      )

    attrs =
      Map.new(spec["attrs"] || %{}, fn {key, value} ->
        key =
          case key do
            "forced" -> :forced?
            "level" -> :level
            "dual_side" -> :dual_side
            "dual_with_cue" -> :dual_with_cue
            _ -> key
          end

        {key, value}
      end)

    if type == :character and attrs[:dual_side] == "right", do: :ok
    attrs = if attrs[:dual_side] == "right", do: Map.put(attrs, :dual?, true), else: attrs
    %Element{id: id, type: type, text: spec["text"], attrs: attrs, origin: (old && old.origin) || :generated}
  end

  defp ensure_id(id, available, context) do
    if !is_binary(id) or
         !(MapSet.member?(available, id) or MapSet.member?(context.new, id) or Map.has_key?(context.restore, id)),
       do: fail({:unknown_or_foreign_id, id})
  end

  defp resolve!(model, target, kind) do
    if target["kind"] not in Enum.map(List.wrap(kind), &to_string/1), do: fail(:wrong_target_kind)
    if target["span"] && kind != :element, do: fail(:span_on_non_element)

    case Fount.Target.resolve(model, target) do
      {:ok, value} -> value
      {:error, error} -> fail(error)
    end
  end

  defp update_element(model, id, text) do
    if !String.valid?(text), do: fail(:invalid_utf8)

    elements =
      Enum.map(model.ir.elements, fn e ->
        if e.id == id, do: %{e | text: text, raw_text: nil, inline: nil, source_span: nil, content_span: nil}, else: e
      end)

    %{model | ir: %{model.ir | elements: elements}, index: Fount.Index.build(%{model.ir | elements: elements})}
  end

  defp update_attrs(model, id, attrs),
    do: %{
      model
      | ir: %{
          model.ir
          | elements:
              Enum.map(model.ir.elements, fn e ->
                if e.id == id, do: %{e | attrs: Map.merge(e.attrs || %{}, attrs), raw_text: nil}, else: e
              end)
        }
    }

  defp refresh_cue_mentions(model, id, text),
    do: %{
      model
      | mentions:
          Map.new(model.mentions, fn {key, m} ->
            {key,
             if(m.element_id == id and m.role == :speaker_cue,
               do: %{m | surface: text, byte_start: 0, byte_end: byte_size(text)},
               else: m
             )}
          end)
    }

  defp insert_index(model, elements, nil) do
    case Enum.find(model.ir.scenes, fn s -> Enum.any?(elements, &(&1.id == s.heading_id)) end) do
      nil -> length(elements)
      s -> Enum.find_index(elements, &(&1.id == s.heading_id))
    end
  end

  defp insert_index(model, elements, id) do
    scene = Query.scene(model, id)
    Enum.find_index(elements, &(&1.id == List.last(scene.element_ids))) + 1
  end

  defp insert(list, index, items) do
    {left, right} = Enum.split(list, index)
    left ++ items ++ right
  end

  defp target(kind, id), do: %{"kind" => kind, "id" => id}
  defp unwrap({:ok, _, _} = value), do: value
  defp unwrap({:ok, _} = value), do: value
  defp unwrap({:error, reason}), do: fail(reason)
  defp fail(reason), do: throw({:edit_error, reason})

  defp lineage(before, after_model),
    do: Enum.map(Fount.Screenplay.diff(before, after_model).scenes.removed, &%{removed_scene_id: &1})

  def spec_ir(model) do
    omitted = MapSet.new(for s <- model.ir.scenes, s.omitted?, id <- s.element_ids, do: id)

    elements =
      model.ir.elements
      |> Enum.reject(&(&1.type in [:note, :boneyard, :section, :synopsis] or MapSet.member?(omitted, &1.id)))
      |> Enum.map(fn e ->
        text = Regex.replace(~r/\[\[.*?\]\]|\/\*.*?\*\//s, e.text, "")
        if text == e.text, do: e, else: %{e | text: text, raw_text: nil, inline: nil}
      end)

    %{model.ir | elements: elements, scenes: Enum.reject(model.ir.scenes, & &1.omitted?)}
  end
end
