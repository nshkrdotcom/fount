defmodule FountWorkshop.Writing.RecoveryCopy do
  @moduledoc false
  alias FountWorkshop.{Candidate, Writing.Context}

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
  end

  defp recovery_operations(base, specs, targets, destination, opts) when specs != [] do
    foreign? = opts[:foreign?]

    with true <-
           length(specs) == length(targets) or
             {:error, :exact_recovery_requires_complete_scene_targets},
         true <-
           foreign? or Enum.all?(specs, &is_nil(Fount.Query.scene(base, &1["id"]))) or
             {:error, :historical_identity_already_present},
         {:ok, placed, copied} <-
           if(foreign?,
             do:
               copied_scenes(
                 base,
                 specs,
                 opts[:registry],
                 opts[:cast_mapping],
                 opts[:speaker_links]
               ),
             else: {:ok, specs, %{}}
           ),
         {:ok, operations} <- place(placed, destination) do
      links =
        if foreign? do
          []
        else
          ids = for scene <- specs, %{"keep" => id} <- scene["elements"], do: id
          cue_link_operations(base, ids, opts[:speaker_links])
        end

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
         {:ok, _} <- Fount.Writing.UTF8Span.extract(current.text, span_tuple(destination_span)) do
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

    with true <-
           (destination_scene && anchor.type != :scene_heading) or
             {:error, :invalid_recovery_anchor},
         true <-
           (length(ids) == length(Enum.uniq(ids)) and source_order == ids and contiguous) or
             {:error, :noncontiguous_historical_range},
         true <-
           Enum.all?(targets, &(&1["kind"] == "element" and registry[&1["id"]])) or
             {:error, :invalid_historical_elements},
         true <-
           Enum.all?(targets, fn t ->
             is_nil(t["span"]) or
               registry[t["id"]].type in [:action, :note, :centered, :lyric, :transition]
           end) or {:error, :unsupported_recovery_fragment},
         true <-
           Enum.all?(targets, fn t ->
             case attribute(registry[t["id"]], "character_id") || opts[:speaker_links][t["id"]] do
               nil -> true
               id -> not opts[:foreign?] or Map.has_key?(base.cast, mapping[id])
             end
           end) or {:error, :missing_cast_mapping},
         true <-
           Enum.all?(targets, fn t ->
             case attribute(registry[t["id"]], "dual_with_cue") do
               nil -> true
               id -> id in ids
             end
           end) or {:error, :incomplete_dual_dialogue_copy},
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

      links =
        if opts[:foreign?],
          do: [],
          else:
            cue_link_operations(base, for(%{"keep" => id} <- specs, do: id), opts[:speaker_links])

      {:ok, [op] ++ links, copied,
       if(opts[:foreign?], do: "cross_screenplay_range_copy", else: "exact_range_recovery")}
    end
  end

  defp recovery_operations(_, [], _, _, _), do: {:error, :unsupported_exact_recovery_targets}

  defp range_specs(base, targets, registry, local, mapping, foreign?, speaker_links) do
    Enum.reduce_while(targets, {:ok, [], %{}}, fn target, {:ok, specs, copied} ->
      id = target["id"]
      element = registry[id]

      if not foreign? and is_nil(target["span"]) and is_nil(Fount.Query.node(base, id)) do
        {:cont, {:ok, specs ++ [%{"keep" => id}], copied}}
      else
        case extract_source(element.text, target["span"]) do
          {:ok, text} ->
            attrs = Fount.Screenplay.Model.plain(element.attrs || %{})
            character_id = attrs["character_id"] || speaker_links[id]
            partner = attrs["dual_with_cue"]

            attrs =
              if character_id,
                do:
                  Map.put(
                    attrs,
                    "character_id",
                    if(foreign?, do: mapping[character_id], else: character_id)
                  ),
                else: attrs

            partner_reference =
              if partner && not foreign? && is_nil(Fount.Query.node(base, partner)) &&
                   Enum.any?(targets, &(&1["id"] == partner and is_nil(&1["span"]))),
                 do: partner,
                 else: local[partner]

            attrs =
              if partner, do: Map.put(attrs, "dual_with_cue", partner_reference), else: attrs

            spec = %{
              "local_id" => local[id],
              "type" => to_string(element.type),
              "text" => text,
              "attrs" => attrs
            }

            {:cont, {:ok, specs ++ [spec], Map.put(copied, id, local[id])}}

          error ->
            {:halt, error}
        end
      end
    end)
  end

  defp cue_link_operations(base, ids, speaker_links) do
    for id <- ids,
        character_id = speaker_links[id],
        is_binary(character_id),
        Map.has_key?(base.cast, character_id),
        do: %{
          "kind" => "link_speaker",
          "target" => %{"kind" => "element", "id" => id},
          "value" => %{"character_id" => character_id}
        }
  end

  defp extract_source(text, nil), do: {:ok, text}
  defp extract_source(text, span), do: Fount.Writing.UTF8Span.extract(text, span_tuple(span))
  defp span_tuple(%{"byte_start" => first, "byte_end" => last}), do: {first, last}
  defp span_tuple(_), do: {-1, -1}

  defp copied_scenes(base, specs, registry, cast_mapping, speaker_links)
       when is_map(cast_mapping) do
    with true <-
           Enum.all?(cast_mapping, fn {source_id, destination_id} ->
             is_binary(source_id) and is_binary(destination_id) and
               Map.has_key?(base.cast, destination_id)
           end) or {:error, :invalid_cast_mapping} do
      source_ids =
        Enum.flat_map(specs, fn spec ->
          [spec["id"] | Enum.map(spec["elements"], & &1["keep"])]
        end)

      local =
        source_ids
        |> Enum.with_index()
        |> Map.new(fn {id, n} -> {id, "new:copy_#{n}"} end)

      converted =
        Enum.map(specs, fn scene ->
          body =
            Enum.map(scene["elements"], fn %{"keep" => id} ->
              element = registry[id]
              attrs = Fount.Screenplay.Model.plain(element.attrs || %{})
              character_id = attrs["character_id"] || speaker_links[id]
              partner = attrs["dual_with_cue"]

              attrs =
                attrs
                |> then(fn a ->
                  if character_id,
                    do: Map.put(a, "character_id", cast_mapping[character_id]),
                    else: a
                end)
                |> then(fn a ->
                  if partner, do: Map.put(a, "dual_with_cue", local[partner]), else: a
                end)

              %{
                "local_id" => local[id],
                "type" => to_string(element.type),
                "text" => element.text,
                "attrs" => attrs
              }
            end)

          %{
            "local_id" => local[scene["id"]],
            "heading" => scene["heading"],
            "number" => scene["number"],
            "omitted" => scene["omitted"],
            "elements" => body
          }
        end)

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

      cond do
        Enum.any?(referenced_cast, &(not Map.has_key?(cast_mapping, &1))) ->
          {:error, :missing_cast_mapping}

        Enum.any?(referenced_partners, &(not Map.has_key?(local, &1))) ->
          {:error, :incomplete_dual_dialogue_copy}

        true ->
          {:ok, converted, local}
      end
    end
  end

  defp copied_scenes(_, _, _, _, _), do: {:error, :explicit_cast_mapping_required}

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
