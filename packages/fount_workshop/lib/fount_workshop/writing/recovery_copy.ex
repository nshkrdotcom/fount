defmodule FountWorkshop.Writing.RecoveryCopy do
  @moduledoc false
  alias Fount.Screenplay.Model
  alias Fount.Writing.UTF8Span
  alias FountWorkshop.Candidate
  alias FountWorkshop.Writing.Context

  def propose(base, request, strategy, context, opts) do
    source = context.data["historical_source"]
    specs = source["scene_specs"] || []
    targets = request["options"]["source_targets"]
    foreign? = source["screenplay_id"] not in [nil, base.id]

    with {:ok, operations, copied_from, recovery_mode} <-
           recovery_operations(base, specs, targets, request["options"]["destination"],
             foreign?: foreign?,
             registry: context.restore_registry,
             cast_mapping: request["options"]["cast_mapping"],
             speaker_links: source["speaker_links"] || %{}
           ) do
      group = %{
        "id" => "historical-copy",
        "title" => "Restore selected historical material",
        "reason" => "Explicit writer request for exact historical text, without adaptation",
        "depends_on" => [],
        "addresses_notes" => [],
        "evidence_ids" => Enum.map(context.evidence, & &1["evidence_id"]),
        "operations" => operations,
        "origin" => "writer_edit"
      }

      proposal = %{
        "version" => 1,
        "base_revision_id" => base.revision.id,
        "strategy_id" => strategy["id"],
        "summary" => strategy["title"],
        "groups" => [group],
        "inventions" => [],
        "unresolved_questions" => []
      }

      options =
        Context.compile_options(base, request, context, opts)
        |> Keyword.put(:writer_edit, true)
        |> Keyword.put(:strategy, strategy)
        |> Keyword.put(:lineage, [
          %{
            "operation" => "historical_copy",
            "source_revision_id" => source["revision_id"],
            "source_targets" => targets
          }
        ])

      compile_candidate(base, proposal, options, copied_from, recovery_mode, source)
    end
  end

  defp compile_candidate(base, proposal, options, copied_from, recovery_mode, source) do
    with {:ok, candidate} <- Candidate.compile(base, proposal, options) do
      allocated = candidate["provenance"]["allocated_ids"] || %{}

      copied_from =
        Map.new(copied_from, fn {source_id, local_id} -> {source_id, allocated[local_id]} end)

      {:ok,
       put_in(candidate, ["provenance", "recovery"], %{
         "mode" => recovery_mode,
         "source_screenplay_id" => source["screenplay_id"] || base.id,
         "source_revision_id" => source["revision_id"],
         "copied_from" => copied_from,
         "generated_text" => false
       })}
    end
  end

  defp recovery_operations(base, specs, targets, destination, opts) when specs != [] do
    foreign? = opts[:foreign?]

    with true <-
           length(specs) == length(targets) or
             {:error, :exact_recovery_requires_complete_scene_targets},
         true <-
           foreign? or Enum.all?(specs, &is_nil(Fount.Query.scene(base, &1["id"]))) or
             {:error, :historical_identity_already_present},
         {:ok, placed, copied} <- scenes_for_copy(base, specs, opts),
         {:ok, operations} <- place(placed, destination) do
      links = scene_links(base, specs, opts)

      {:ok, operations ++ links, copied,
       if(foreign?, do: "cross_screenplay_copy", else: "exact_copy")}
    end
  end

  defp recovery_operations(
         base,
         [],
         [%{"kind" => "element", "id" => source_id} = target],
         %{
           "kind" => "replace_element_span",
           "element_id" => destination_id,
           "span" => destination_span
         },
         opts
       ) do
    source = opts[:registry][source_id]
    current = Fount.Query.node(base, destination_id)

    with true <- not opts[:foreign?] or {:error, :cross_screenplay_fragment_requires_copy},
         true <-
           (source && current && source.type == current.type) or
             {:error, :incompatible_recovery_elements},
         true <-
           source.type in [
             :action,
             :dialogue,
             :parenthetical,
             :lyric,
             :note,
             :centered,
             :transition
           ] or
             {:error, :unsupported_recovery_fragment},
         {:ok, excerpt} <- extract_source(source.text, target["span"]),
         {:ok, _} <- UTF8Span.extract(current.text, span_tuple(destination_span)) do
      {:ok,
       [
         %{
           "kind" => "replace_text",
           "target" => %{"kind" => "element", "id" => destination_id, "span" => destination_span},
           "value" => excerpt
         }
       ], %{}, "exact_fragment_recovery"}
    end
  end

  defp recovery_operations(
         base,
         [],
         targets,
         %{"kind" => "insert_after_element", "element_id" => anchor_id},
         opts
       )
       when is_list(targets) and targets != [] do
    registry = opts[:registry]
    ids = Enum.map(targets, & &1["id"])
    anchor = Fount.Query.node(base, anchor_id)
    destination_scene = anchor && Fount.Query.scene_for(base, anchor_id)

    source_scene =
      registry
      |> Map.values()
      |> Enum.find(fn
        %Fount.IR.Scene{element_ids: source_ids} -> Enum.all?(ids, &(&1 in source_ids))
        _ -> false
      end)

    source_order =
      if source_scene, do: Enum.filter(source_scene.element_ids, &(&1 in ids)), else: []

    first_index = if source_scene, do: Enum.find_index(source_scene.element_ids, &(&1 == hd(ids)))

    contiguous =
      source_scene && Enum.slice(source_scene.element_ids, first_index, length(ids)) == ids

    local = Map.new(Enum.with_index(ids), fn {id, n} -> {id, "new:copy_range_#{n}"} end)
    mapping = opts[:cast_mapping] || %{}

    checks = %{
      base: base,
      targets: targets,
      ids: ids,
      registry: registry,
      mapping: mapping,
      opts: opts,
      anchor: anchor,
      destination_scene: destination_scene,
      source_order: source_order,
      contiguous: contiguous
    }

    with :ok <- validate_range(checks),
         {:ok, specs, copied} <-
           range_specs(
             base,
             targets,
             registry,
             local,
             mapping,
             opts[:foreign?],
             opts[:speaker_links]
           ) do
      op = %{
        "kind" => "insert_elements",
        "target" => %{"kind" => "scene", "id" => destination_scene.id},
        "value" => %{"position" => "after", "anchor_id" => anchor_id, "elements" => specs}
      }

      links = range_links(base, specs, opts)

      {:ok, [op] ++ links, copied,
       if(opts[:foreign?], do: "cross_screenplay_range_copy", else: "exact_range_recovery")}
    end
  end

  defp recovery_operations(_, [], _, _, _), do: {:error, :unsupported_exact_recovery_targets}

  defp scenes_for_copy(base, specs, opts) do
    if opts[:foreign?] do
      copied_scenes(base, specs, opts[:registry], opts[:cast_mapping], opts[:speaker_links])
    else
      {:ok, specs, %{}}
    end
  end

  defp scene_links(base, specs, opts) do
    if opts[:foreign?] do
      []
    else
      ids = for scene <- specs, %{"keep" => id} <- scene["elements"], do: id
      cue_link_operations(base, ids, opts[:speaker_links])
    end
  end

  defp validate_range(c) do
    with true <- valid_anchor?(c) or {:error, :invalid_recovery_anchor},
         true <- contiguous_range?(c) or {:error, :noncontiguous_historical_range},
         true <- valid_range_targets?(c) or {:error, :invalid_historical_elements},
         true <- valid_range_spans?(c) or {:error, :unsupported_recovery_fragment},
         true <- mapped_speakers?(c) or {:error, :missing_cast_mapping},
         true <- complete_dual_links?(c) or {:error, :incomplete_dual_dialogue_copy} do
      :ok
    end
  end

  defp valid_anchor?(c), do: c.destination_scene && c.anchor.type != :scene_heading

  defp contiguous_range?(c),
    do: length(c.ids) == length(Enum.uniq(c.ids)) and c.source_order == c.ids and c.contiguous

  defp valid_range_targets?(c),
    do: Enum.all?(c.targets, &(&1["kind"] == "element" and c.registry[&1["id"]]))

  defp valid_range_spans?(c) do
    Enum.all?(c.targets, fn t ->
      is_nil(t["span"]) or
        c.registry[t["id"]].type in [:action, :note, :centered, :lyric, :transition]
    end)
  end

  defp mapped_speakers?(c) do
    Enum.all?(c.targets, fn t ->
      case attribute(c.registry[t["id"]], "character_id") || c.opts[:speaker_links][t["id"]] do
        nil -> true
        id -> not c.opts[:foreign?] or Map.has_key?(c.base.cast, c.mapping[id])
      end
    end)
  end

  defp complete_dual_links?(c) do
    Enum.all?(c.targets, fn t ->
      case attribute(c.registry[t["id"]], "dual_with_cue") do
        nil -> true
        id -> id in c.ids
      end
    end)
  end

  defp range_links(base, specs, opts) do
    if opts[:foreign?],
      do: [],
      else: cue_link_operations(base, for(%{"keep" => id} <- specs, do: id), opts[:speaker_links])
  end

  defp range_specs(base, targets, registry, local, mapping, foreign?, speaker_links) do
    context = %{
      base: base,
      targets: targets,
      registry: registry,
      local: local,
      mapping: mapping,
      foreign?: foreign?,
      speaker_links: speaker_links
    }

    Enum.reduce_while(targets, {:ok, [], %{}}, fn target, {:ok, specs, copied} ->
      case range_spec(target, context) do
        {:ok, spec, nil} ->
          {:cont, {:ok, specs ++ [spec], copied}}

        {:ok, spec, source_id} ->
          {:cont, {:ok, specs ++ [spec], Map.put(copied, source_id, local[source_id])}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp range_spec(target, c) do
    id = target["id"]

    if not c.foreign? and is_nil(target["span"]) and is_nil(Fount.Query.node(c.base, id)) do
      {:ok, %{"keep" => id}, nil}
    else
      element = c.registry[id]

      with {:ok, text} <- extract_source(element.text, target["span"]) do
        attrs = Model.plain(element.attrs || %{})
        attrs = copy_attrs(attrs, id, c)

        {:ok,
         %{
           "local_id" => c.local[id],
           "type" => to_string(element.type),
           "text" => text,
           "attrs" => attrs
         }, id}
      end
    end
  end

  defp copy_attrs(attrs, id, c) do
    character_id = attrs["character_id"] || c.speaker_links[id]
    partner = attrs["dual_with_cue"]

    attrs =
      if character_id,
        do: Map.put(attrs, "character_id", copied_character(character_id, c)),
        else: attrs

    if partner, do: Map.put(attrs, "dual_with_cue", partner_reference(partner, c)), else: attrs
  end

  defp copied_character(id, %{foreign?: true} = c), do: c.mapping[id]
  defp copied_character(id, _), do: id

  defp partner_reference(partner, c) do
    if partner && not c.foreign? && is_nil(Fount.Query.node(c.base, partner)) &&
         Enum.any?(c.targets, &(&1["id"] == partner and is_nil(&1["span"]))) do
      partner
    else
      c.local[partner]
    end
  end

  defp cue_link_operations(base, ids, speaker_links) do
    for id <- ids,
        character_id = speaker_links[id],
        is_binary(character_id),
        Map.has_key?(base.cast, character_id),
        do: %{
          "kind" => "link_speaker",
          "target" => %{
            "kind" => "dialogue_block",
            "id" => Fount.ID.v5(base.id, ["dialogue-block:", id])
          },
          "value" => %{"character_id" => character_id}
        }
  end

  defp extract_source(text, nil), do: {:ok, text}
  defp extract_source(text, span), do: UTF8Span.extract(text, span_tuple(span))
  defp span_tuple(%{"byte_start" => first, "byte_end" => last}), do: {first, last}
  defp span_tuple(_), do: {-1, -1}

  defp copied_scenes(base, specs, registry, cast_mapping, speaker_links)
       when is_map(cast_mapping) do
    with true <- valid_cast_mapping?(base, cast_mapping) or {:error, :invalid_cast_mapping} do
      source_ids =
        Enum.flat_map(specs, fn spec ->
          [spec["id"] | Enum.map(spec["elements"], & &1["keep"])]
        end)

      local =
        source_ids
        |> Enum.with_index()
        |> Map.new(fn {id, n} -> {id, "new:copy_#{n}"} end)

      converted =
        Enum.map(specs, &convert_scene(&1, registry, local, cast_mapping, speaker_links))

      referenced_cast =
        for scene <- specs,
            %{"keep" => id} <- scene["elements"],
            character_id = attribute(registry[id], "character_id") || speaker_links[id],
            is_binary(character_id),
            do: character_id

      referenced_partners =
        for scene <- specs,
            %{"keep" => id} <- scene["elements"],
            partner = attribute(registry[id], "dual_with_cue"),
            is_binary(partner),
            do: partner

      validate_copied_links(referenced_cast, referenced_partners, cast_mapping, local, converted)
    end
  end

  defp copied_scenes(_, _, _, _, _), do: {:error, :explicit_cast_mapping_required}

  defp valid_cast_mapping?(base, cast_mapping) do
    Enum.all?(cast_mapping, fn {source_id, destination_id} ->
      is_binary(source_id) and is_binary(destination_id) and
        Map.has_key?(base.cast, destination_id)
    end)
  end

  defp validate_copied_links(cast, partners, mapping, local, converted) do
    cond do
      Enum.any?(cast, &(not Map.has_key?(mapping, &1))) ->
        {:error, :missing_cast_mapping}

      Enum.any?(partners, &(not Map.has_key?(local, &1))) ->
        {:error, :incomplete_dual_dialogue_copy}

      true ->
        {:ok, converted, local}
    end
  end

  defp convert_scene(scene, registry, local, cast_mapping, speaker_links) do
    body =
      Enum.map(scene["elements"], fn %{"keep" => id} ->
        convert_element(id, registry, local, cast_mapping, speaker_links)
      end)

    %{
      "local_id" => local[scene["id"]],
      "heading" => scene["heading"],
      "number" => scene["number"],
      "omitted" => scene["omitted"],
      "elements" => body
    }
  end

  defp convert_element(id, registry, local, cast_mapping, speaker_links) do
    element = registry[id]
    attrs = Model.plain(element.attrs || %{})
    character_id = attrs["character_id"] || speaker_links[id]
    partner = attrs["dual_with_cue"]

    attrs =
      if character_id, do: Map.put(attrs, "character_id", cast_mapping[character_id]), else: attrs

    attrs = if partner, do: Map.put(attrs, "dual_with_cue", local[partner]), else: attrs

    %{
      "local_id" => local[id],
      "type" => to_string(element.type),
      "text" => element.text,
      "attrs" => attrs
    }
  end

  defp attribute(element, key) do
    attrs = element.attrs || %{}
    Map.get(attrs, key, Map.get(attrs, String.to_existing_atom(key)))
  end

  defp place(scenes, %{"kind" => "replace_range", "scene_ids" => ids}) do
    {:ok, [%{"kind" => "replace_sequence", "value" => %{"scene_ids" => ids, "scenes" => scenes}}]}
  end

  defp place(scenes, %{"kind" => kind} = destination)
       when kind in ["start", "after_scene", "between_scenes"] do
    {ops, _} =
      Enum.map_reduce(scenes, destination["after_scene_id"], fn scene, after_id ->
        {%{
           "kind" => "insert_scene",
           "value" => %{"after_scene_id" => after_id, "scene" => scene}
         }, scene["id"] || scene["local_id"]}
      end)

    {:ok, ops}
  end

  defp place(_, _), do: {:error, :exact_scene_recovery_requires_scene_destination}
end
