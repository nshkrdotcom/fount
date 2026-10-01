defmodule FountWeb.CreativeWorkspace do
  @moduledoc "Host-only UX02 projections and validation for named creative-work selections."

  alias Fount.{Persistence, Query}
  alias FountWeb.{ProductionTools, ScreenplayIndex}

  @max_scope 64
  @max_protected 32
  @max_picker 300
  @pass_profiles ~w(dialogue_subtext action_visual sound_space cinematic_rhythm transition brevity dry_comedy tension custom)

  def max_scope, do: @max_scope
  def max_protected, do: @max_protected
  def pass_profiles, do: @pass_profiles

  def scope_options(screenplay) do
    whole = [%{value: "whole", label: "Whole screenplay", kind: "screenplay"}]

    scenes =
      screenplay
      |> ScreenplayIndex.scene_index()
      |> Enum.map(fn scene ->
        suffix = if scene.omitted?, do: " · omitted", else: ""

        %{
          value: "scene:#{scene.id}",
          label: "Scene #{scene.ordinal} · #{scene.heading || "Untitled"}#{suffix}",
          kind: "scene"
        }
      end)

    characters =
      screenplay
      |> ProductionTools.character_profiles()
      |> Enum.map(fn character ->
        %{
          value: "character:#{character.id}",
          label:
            "Character · #{character.display_name} · #{character.dialogue_block_count} dialogue blocks",
          kind: "character"
        }
      end)

    elements =
      screenplay.ir.elements
      |> Enum.reject(&(&1.type in [:blank]))
      |> Enum.take(max(@max_picker - length(scenes) - length(characters) - 1, 0))
      |> Enum.map(fn element ->
        scene = Query.scene_for(screenplay, element.id)
        scene_ordinal = scene_ordinal(screenplay, scene && scene.id)
        excerpt = human_excerpt(element.text, 78)

        %{
          value: "element:#{element.id}",
          label: "#{scene_prefix(scene_ordinal)}#{human_type(element.type)} · #{excerpt}",
          kind: "element"
        }
      end)

    Enum.take(whole ++ scenes ++ characters ++ elements, @max_picker)
  end

  def protection_options(screenplay) do
    screenplay.ir.elements
    |> Enum.reject(&(&1.type in [:blank, :page_break, :section, :synopsis]))
    |> Enum.take(@max_picker)
    |> Enum.map(fn element ->
      scene = Query.scene_for(screenplay, element.id)
      ordinal = scene_ordinal(screenplay, scene && scene.id)

      %{
        value: "element:#{element.id}",
        label:
          "#{scene_prefix(ordinal)}#{human_type(element.type)} · #{human_excerpt(element.text, 86)}"
      }
    end)
  end

  def selection_from_values(screenplay, values) do
    values = values |> list() |> Enum.uniq()

    cond do
      "whole" in values ->
        {:ok, %{"whole_screenplay" => true}}

      values == [] ->
        {:error, :selection_required}

      length(values) > @max_scope ->
        {:error, :selection_limit}

      true ->
        with {:ok, targets} <- parse_targets(screenplay, values),
             {:ok, _} <- Fount.Selection.selected_ids(screenplay, %{"targets" => targets}) do
          {:ok, %{"targets" => targets}}
        end
    end
  end

  def protected_text(screenplay, values) do
    values = values |> list() |> Enum.uniq()

    if length(values) > @max_protected do
      {:error, :protection_limit}
    else
      Enum.reduce_while(values, {:ok, []}, &collect_protected_passage(screenplay, &1, &2))
      |> reverse_ok()
    end
  end

  defp collect_protected_passage(screenplay, value, {:ok, acc}) do
    with {:ok, %{"kind" => "element", "id" => id} = target} <- parse_target(screenplay, value),
         %{text: text} when is_binary(text) and text != "" <- Query.node(screenplay, id) do
      passage = %{"id" => "writer-protected:#{id}", "target" => target, "text" => text}
      {:cont, {:ok, [passage | acc]}}
    else
      _ -> {:halt, {:error, :invalid_protected_passage}}
    end
  end

  def action_attrs(repo, screenplay, action, params, selection, protected_text) do
    common =
      %{
        "protected_text" => protected_text,
        "protected_strengths" => split_lines(params["protected_strengths"], 12),
        "intended_effect" => blank_to_nil(params["intended_effect"]),
        "pending_question" => blank_to_nil(params["pending_question"])
      }
      |> compact_map()

    with {:ok, specific} <- action_specific(repo, screenplay, action, params, selection) do
      {:ok, Map.merge(common, specific)}
    end
  end

  def historical_sources(repo, screenplay) do
    Persistence.history(repo, screenplay.id, limit: 13)
    |> Enum.drop(1)
    |> Enum.flat_map(&historical_source(repo, screenplay, &1))
  end

  defp historical_source(repo, screenplay, revision) do
    case Persistence.load_revision(repo, screenplay.id, revision.id) do
      {:ok, historical} ->
        scenes =
          historical
          |> ScreenplayIndex.scene_index()
          |> Enum.take(40)
          |> Enum.map(&historical_scene/1)

        [%{id: revision.id, label: historical_label(revision), scenes: scenes}]

      _ ->
        []
    end
  end

  defp historical_scene(scene),
    do: %{
      value: "scene:#{scene.id}",
      label: "Scene #{scene.ordinal} · #{scene.heading || "Untitled"}"
    }

  def character_dialogue(screenplay, character_id, limit \\ 100) do
    character = screenplay.cast[character_id]

    if character do
      rows =
        screenplay
        |> Query.character_dialogue(character_id)
        |> Enum.with_index(1)
        |> Enum.map(&dialogue_row(screenplay, &1))

      {:ok, %{character: character, total: length(rows), rows: Enum.take(rows, limit)}}
    else
      {:error, :character_not_found}
    end
  end

  defp dialogue_row(screenplay, {block, ordinal}) do
    cue = Query.node(screenplay, block.cue_id)
    scene = Query.scene_for(screenplay, block.cue_id)
    scene_heading = if scene, do: Query.node(screenplay, scene.heading_id), else: nil

    body =
      block.body_ids
      |> Enum.map(&Query.node(screenplay, &1))
      |> Enum.reject(&is_nil/1)

    %{
      ordinal: ordinal,
      cue_id: block.cue_id,
      character: cue && cue.text,
      scene_id: scene && scene.id,
      scene_heading: scene_heading && scene_heading.text,
      lines: Enum.map(body, &%{id: &1.id, type: &1.type, text: &1.text})
    }
  end

  defp action_specific(_repo, _screenplay, "develop", params, _selection) do
    placement =
      case params["placement"] do
        "after_scene:" <> id -> %{"kind" => "after_scene", "after_scene_id" => id}
        _ -> %{"kind" => "start"}
      end

    {:ok,
     %{
       "placement" => placement,
       "brief" => blank_to_nil(params["brief"]) || blank_to_nil(params["question"])
     }}
  end

  defp action_specific(_repo, _screenplay, "rewrite", params, _selection) do
    case blank_to_nil(params["question"]) do
      nil -> {:error, :direction_required}
      direction -> {:ok, %{"profile" => "custom", "direction" => direction}}
    end
  end

  defp action_specific(_repo, _screenplay, "pass", params, _selection) do
    profile =
      if params["profile"] in @pass_profiles, do: params["profile"], else: "dialogue_subtext"

    direction = blank_to_nil(params["direction"] || params["question"])

    if profile == "custom" and is_nil(direction),
      do: {:error, :direction_required},
      else: {:ok, compact_map(%{"profile" => profile, "direction" => direction})}
  end

  defp action_specific(_repo, _screenplay, "alternatives", params, _selection) do
    with {:ok, count} <- bounded_integer(params["alternatives"], 2, 6, 3) do
      {:ok,
       %{
         "alternatives" => count,
         "approaches" => split_lines(params["approaches"], count),
         "allow_brief_departure" => truthy?(params["allow_brief_departure"])
       }}
    end
  end

  defp action_specific(_repo, _screenplay, "sequence", params, _selection) do
    with {:ok, count} <- bounded_integer(params["target_scene_count"], 1, 80, nil) do
      {:ok, %{"target_scene_count" => count}}
    end
  end

  defp action_specific(_repo, screenplay, "character", params, _selection) do
    id = params["character_id"]

    cond do
      not is_binary(id) or is_nil(screenplay.cast[id]) -> {:error, :character_required}
      blank_to_nil(params["question"]) == nil -> {:error, :direction_required}
      true -> {:ok, %{"character_id" => id, "direction" => String.trim(params["question"])}}
    end
  end

  defp action_specific(_repo, _screenplay, "propagate", _params, selection),
    do: {:ok, %{"repair_scope" => selection}}

  defp action_specific(_repo, screenplay, "notes", params, _selection) do
    ids = list(params["note_ids"]) |> Enum.uniq()

    valid? =
      ids != [] and
        Enum.all?(ids, fn id ->
          case screenplay.authored_items[id] do
            %{"kind" => "note"} -> true
            _ -> false
          end
        end)

    if valid?,
      do: {:ok, %{"note_ids" => ids, "external_notes" => []}},
      else: {:error, :note_required}
  end

  defp action_specific(repo, screenplay, "recover", params, _selection) do
    revision_id = params["source_revision_id"]

    with true <-
           (is_binary(revision_id) and revision_id != screenplay.revision.id) or
             {:error, :historical_source_required},
         true <- list(params["source_targets"]) != [] or {:error, :historical_scene_required},
         {:ok, source} <- Persistence.load_revision(repo, screenplay.id, revision_id),
         {:ok, source_selection} <- selection_from_values(source, params["source_targets"]),
         {:ok, targets} <- recover_source_targets(source, source_selection),
         {:ok, destination} <- recovery_destination(screenplay, params) do
      {:ok,
       %{
         "source_revision_id" => revision_id,
         "source_screenplay_id" => screenplay.id,
         "source_targets" => targets,
         "destination" => destination,
         "adapt" => truthy?(params["adapt"])
       }}
    else
      false -> {:error, :historical_source_required}
      {:error, _} = error -> error
    end
  end

  defp action_specific(_repo, _screenplay, "investigate", params, _selection),
    do: {:ok, %{"concern" => String.trim(params["question"] || ""), "write_fixes" => false}}

  defp action_specific(_, _, _, _, _), do: {:error, :unsupported_action}

  defp recover_source_targets(source, %{"targets" => targets}) do
    case Fount.Selection.selected_ids(source, %{"targets" => targets}) do
      {:ok, _} -> {:ok, targets}
      _ -> {:error, :recovery_targets_missing_from_history}
    end
  end

  defp recover_source_targets(source, %{"whole_screenplay" => true}) do
    case source.ir.scenes do
      [scene | _] -> {:ok, [%{"kind" => "scene", "id" => scene.id}]}
      _ -> {:error, :recovery_targets_missing_from_history}
    end
  end

  defp recovery_destination(screenplay, params) do
    case params["destination"] do
      "after_scene:" <> id ->
        if Query.scene(screenplay, id),
          do: {:ok, %{"kind" => "after_scene", "after_scene_id" => id}},
          else: {:error, :recovery_destination_missing}

      _ ->
        {:ok, %{"kind" => "start"}}
    end
  end

  defp parse_targets(screenplay, values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case parse_target(screenplay, value) do
        {:ok, target} -> {:cont, {:ok, [target | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> reverse_ok()
  end

  defp parse_target(screenplay, value) when is_binary(value) do
    case String.split(value, ":", parts: 2) do
      [kind, id] when kind in ~w(scene element character) and id != "" ->
        target = %{"kind" => kind, "id" => id}

        case Fount.Target.resolve(screenplay, target) do
          {:ok, _} -> {:ok, target}
          _ -> {:error, :selection_stale}
        end

      _ ->
        {:error, :invalid_selection}
    end
  end

  defp parse_target(_, _), do: {:error, :invalid_selection}

  defp historical_label(revision) do
    message = blank_to_nil(revision.message) || "Saved revision"
    date = revision.created_at && Calendar.strftime(revision.created_at, "%Y-%m-%d %H:%M")
    [message, date] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")
  end

  defp scene_ordinal(screenplay, scene_id) when is_binary(scene_id) do
    screenplay.ir.scenes
    |> Enum.find_index(&(&1.id == scene_id))
    |> case do
      nil -> nil
      index -> index + 1
    end
  end

  defp scene_ordinal(_, _), do: nil
  defp scene_prefix(nil), do: ""
  defp scene_prefix(ordinal), do: "Scene #{ordinal} · "

  defp human_type(type), do: type |> to_string() |> String.replace("_", " ")

  defp human_excerpt(text, size) do
    text = text |> to_string() |> String.replace(~r/\s+/u, " ") |> String.trim()
    if String.length(text) > size, do: String.slice(text, 0, size - 1) <> "…", else: text
  end

  defp split_lines(nil, _limit), do: []

  defp split_lines(value, limit) when is_binary(value) do
    value
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(limit)
  end

  defp split_lines(values, limit) when is_list(values),
    do:
      values
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.take(limit)

  defp split_lines(_, _), do: []

  defp bounded_integer(nil, _min, _max, nil), do: {:error, :number_required}
  defp bounded_integer(nil, _min, _max, default), do: {:ok, default}

  defp bounded_integer(value, min, max, default) do
    parsed = if is_integer(value), do: {value, ""}, else: Integer.parse(to_string(value || ""))

    case parsed do
      {number, ""} when number >= min and number <= max -> {:ok, number}
      _ when not is_nil(default) -> {:ok, default}
      _ -> {:error, :invalid_number}
    end
  end

  defp compact_map(map), do: Map.reject(map, fn {_key, value} -> value in [nil, [], ""] end)
  defp reverse_ok({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_ok(error), do: error
  defp list(nil), do: []
  defp list(value) when is_list(value), do: Enum.filter(value, &is_binary/1)
  defp list(value) when is_binary(value), do: [value]
  defp list(_), do: []
  defp truthy?(value), do: value in [true, "true", "on", "1"]

  defp blank_to_nil(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp blank_to_nil(_), do: nil
end
