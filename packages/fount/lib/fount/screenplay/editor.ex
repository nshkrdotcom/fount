defmodule Fount.Screenplay.Editor do
  @moduledoc false
  alias Fount.ID
  alias Fount.IR.Element
  alias Fount.IR.Scene
  alias Fount.IR.TitlePage
  alias Fount.Query
  alias Fount.Screenplay
  alias Fount.Screenplay.Model
  alias Fount.Writing.LocalReferences
  alias Fount.Writing.Schema
  alias Fount.Writing.UTF8Span

  @types ~w(action character dialogue parenthetical transition centered lyric section synopsis page_break note boneyard blank)
  @type_atoms Map.new(@types, &{&1, String.to_atom(&1)})
  @attr_keys %{"forced" => :forced?, "level" => :level, "dual_side" => :dual_side, "dual_with_cue" => :dual_with_cue}

  def apply(base, operations, opts) when is_list(operations) do
    normalized = Enum.map(operations, &normalize/1)

    Enum.each(normalized, &validate_operation/1)

    {:ok, compiled, mapping} = unwrap(LocalReferences.compile(normalized, Keyword.put(opts, :screenplay_id, base.id)))
    allowed_new = MapSet.new(Map.values(mapping))
    context = %{new: allowed_new, restore: Keyword.get(opts, :restore_registry, %{})}

    updated =
      Enum.reduce(compiled, Model.refresh(base), fn op, model -> step(model, op, context) |> Model.refresh() end)

    updated = updated |> link_explicit_cues() |> Model.refresh()
    diagnostics = Fount.Validate.screenplay(updated)
    if diagnostics != [], do: fail({:invalid_model, diagnostics})
    model = advance_revision(base, updated, opts)

    impact = Fount.ChangeImpact.between(base, model)

    annotations = Map.reject(model.annotations, &stale_annotation?(model, impact, &1))

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

  def apply(_, _, _), do: {:error, :operations_must_be_a_list}

  defp validate_operation(%{"kind" => "set_character_cue"}), do: :ok

  defp validate_operation(operation) do
    case Schema.validate("operations.json", operation) do
      :ok -> :ok
      {:error, errors} -> fail({:operation_contract, errors})
    end
  end

  defp advance_revision(base, updated, opts) do
    if Model.content(updated) == Model.content(base) do
      base
    else
      revision = %Fount.Revision{
        id: ID.v4(),
        parent_id: base.revision.id,
        created_at: DateTime.utc_now(),
        actor: Keyword.get(opts, :actor)
      }

      %{updated | revision: revision} |> Model.refresh()
    end
  end

  defp stale_annotation?(model, impact, {_, annotation}) do
    id = annotation.target.node_id

    (is_nil(Query.node(model, id)) and is_nil(Query.scene(model, id)) and id != model.id) or
      (annotation.provenance.producer != "writer" and Enum.any?(impact.changed_targets, &(&1.id == id)))
  end

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
    validate_text_target(kind, element.type)
    text = replace_span(element.text, target["span"], text)

    model = update_element(model, element.id, text)

    maybe_update_cue(model, kind, element.id, text)
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
    {scene, elements} = scene_spec(model, spec, %{}, context)
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

    available = Map.new(Enum.flat_map(scenes, & &1.element_ids) ++ ids, &{&1, true})
    pairs = Enum.map(specs, &scene_spec(model, &1, available, context))
    replacements = Enum.flat_map(pairs, &elem(&1, 1))
    first = Enum.find_index(model.ir.elements, &(&1.id == hd(scenes).heading_id))
    remaining = Enum.reject(model.ir.elements, &Map.has_key?(available, &1.id))
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

    scope = insertion_scope(model, target["kind"], owner)

    anchor = value["anchor_id"]
    position = value["position"]
    if position in ["before", "after"] and anchor not in scope, do: fail(:invalid_anchor)

    index = insertion_index(model, owner, target["kind"], scope, position, anchor)

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
    ensure_id(value["id"], model.cast, context)
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
      |> Enum.filter(&renameable_mention?(&1, c.id, chosen))

    if Enum.any?(chosen, fn id -> not Enum.any?(mentions, &(&1.id == id)) end), do: fail(:unconfirmed_mention)

    model = Enum.reduce(Enum.sort_by(mentions, &{-&1.byte_start}), model, &rename_mention(&1, &2, name))

    %{model | cast: Map.put(model.cast, c.id, %{c | display_name: name})}
  end

  defp step(model, %{"kind" => "put_authored_item", "value" => value}, context) do
    ensure_id(value["id"], model.authored_items, context)

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
    available = Map.new((model.ir.title_page && model.ir.title_page.entries) || [], &{&1.id, true})

    entries =
      Enum.map(entries, fn e ->
        ensure_id(e["id"], available, context)
        %TitlePage.Entry{id: e["id"], key: e["key"], values: e["values"]}
      end)

    %{model | ir: %{model.ir | title_page: %TitlePage{entries: entries}}}
  end

  defp step(_, op, _), do: fail({:invalid_operation, op["kind"]})

  defp validate_text_target("replace_text", type)
       when type not in [:action, :dialogue, :parenthetical, :lyric, :note, :centered, :transition],
       do: fail(:invalid_text_target)

  defp validate_text_target("set_character_cue", type) when type != :character,
    do: fail(:not_a_character_cue)

  defp validate_text_target(_, _), do: :ok
  defp replace_span(_, nil, text), do: text

  defp replace_span(original, %{"byte_start" => first, "byte_end" => last}, text) do
    unwrap(UTF8Span.extract(original, {first, last}))
    binary_part(original, 0, first) <> text <> binary_part(original, last, byte_size(original) - last)
  end

  defp maybe_update_cue(model, "set_character_cue", id, text) do
    model
    |> update_attrs(id, %{forced?: text != String.upcase(text)})
    |> refresh_cue_mentions(id, text)
  end

  defp maybe_update_cue(model, _, _, _), do: model

  defp insertion_scope(_, "scene", owner), do: tl(owner.element_ids)

  defp insertion_scope(model, _, _) do
    model.ir.elements |> Enum.filter(&is_nil(Query.scene_for(model, &1.id))) |> Enum.map(& &1.id)
  end

  defp insertion_index(model, _, _, _, "before", anchor), do: element_index(model, anchor)
  defp insertion_index(model, _, _, _, "after", anchor), do: element_index(model, anchor) + 1
  defp insertion_index(model, owner, "scene", _, "start", _), do: element_index(model, owner.heading_id) + 1
  defp insertion_index(_, _, _, _, "start", _), do: 0
  defp insertion_index(model, owner, kind, [], "end", _), do: insertion_index(model, owner, kind, [], "start", nil)
  defp insertion_index(model, _, _, scope, "end", _), do: element_index(model, List.last(scope)) + 1
  defp insertion_index(_, _, _, _, _, _), do: fail(:invalid_position)
  defp element_index(model, id), do: Enum.find_index(model.ir.elements, &(&1.id == id))

  defp renameable_mention?(mention, character_id, chosen) do
    mention.character_id == character_id and mention.status == :confirmed and
      (mention.role == :speaker_cue or mention.id in chosen)
  end

  defp rename_mention(mention, model, name) do
    element = Query.node(model, mention.element_id)
    suffix = if mention.role == :speaker_cue, do: (Regex.run(~r/\s+\([^)]*\)$/, element.text) || [""]) |> hd(), else: ""

    text =
      binary_part(element.text, 0, mention.byte_start) <>
        name <> suffix <> binary_part(element.text, mention.byte_end, byte_size(element.text) - mention.byte_end)

    model = update_element(model, element.id, text)
    updated = %{mention | surface: name <> suffix, byte_end: mention.byte_start + byte_size(name <> suffix)}
    %{model | mentions: Map.put(model.mentions, mention.id, updated)}
  end

  defp scene_spec(model, spec, available, context) do
    id = spec["id"]
    ensure_id(id, available, context)
    old = Query.scene(model, id) || Map.get(context.restore, id)

    heading = %Element{
      id: (old && old.heading_id) || ID.v5(model.id, ["scene-heading:", id]),
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

    type = Map.fetch!(@type_atoms, spec["type"])
    attrs = Map.new(spec["attrs"] || %{}, fn {key, value} -> {Map.get(@attr_keys, key, key), value} end)
    attrs = if attrs[:dual_side] == "right", do: Map.put(attrs, :dual?, true), else: attrs
    %Element{id: id, type: type, text: spec["text"], attrs: attrs, origin: (old && old.origin) || :generated}
  end

  defp link_explicit_cues(model) do
    Enum.reduce(model.ir.elements, model, &link_element_cue/2)
  end

  defp link_element_cue(element, model) do
    id = (element.attrs || %{})["character_id"]

    if element.type == :character and id do
      case Screenplay.link_cue(model, element.id, id) do
        {:ok, linked} -> %{linked | revision: model.revision}
        {:error, reason} -> fail(reason)
      end
    else
      model
    end
  end

  @spec ensure_id(term(), map(), map()) :: nil
  defp ensure_id(id, available, context) do
    if !is_binary(id) or
         !(Map.has_key?(available, id) or MapSet.member?(context.new, id) or Map.has_key?(context.restore, id)),
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
