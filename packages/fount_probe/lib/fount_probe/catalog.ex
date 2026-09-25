defmodule FountProbe.Catalog do
  @moduledoc "Closed screenplay tool catalog. No model-selected module, function, shell, or storage route."
  @catalog %{
    "inventory" => {~w(selection), ~w(include_summaries)},
    "extract_story" => {~w(selection kinds), ~w(question adjacent_scenes)},
    "search" => {~w(query), ~w(selection filters revision_ids mode limit exact_phrase)},
    "check_constraints" => {~w(constraints), ~w(selection)},
    "knowledge_trace" =>
      {~w(proposition subjects points),
       ~w(access_mode suspicion behavior_element_ids intended_reveal_point)},
    "locate_boundary" =>
      {~w(scene_id proposition projection), ~w(character_id threshold include_prior_context)},
    "dependencies" =>
      {~w(targets selection),
       ~w(record_report_ids include_alternative_support inspect_setup_purpose)},
    "continuity" => {~w(selection), ~w(subjects changed_targets record_report_ids)},
    "scene_mechanics" => {~w(selection), ~w(character_id objective concern include_tactics)},
    "dialogue" => {~w(selection lenses), ~w(character_ids)},
    "voice" => {~w(character_ids selection), ~w(training_targets profiles comparison_groups)},
    "action" => {~w(selection), ~w(direction layout_report_id)},
    "compare" => {~w(before_revision_id after_revision_id constraints), ~w(profile_id)},
    "scene_lift" => {~w(scene_ids constraints), ~w(consequence_scope)},
    "ablate" => {~w(groups proposition point projection), ~w(character_id)},
    "strategy_contrast" => {~w(brief strategies), []}
  }
  @lists ~w(kinds revision_ids constraints subjects points behavior_element_ids targets record_report_ids changed_targets lenses character_ids training_targets comparison_groups scene_ids groups strategies)
  @booleans ~w(include_summaries exact_phrase suspicion include_prior_context include_alternative_support inspect_setup_purpose include_tactics)
  @strings ~w(query question proposition scene_id projection character_id objective concern direction layout_report_id before_revision_id after_revision_id profile_id brief access_mode mode consequence_scope)
  def tools do
    @catalog
    |> Enum.sort()
    |> Enum.map(fn {name, {required, optional}} ->
      %{
        "name" => name,
        "version" => 1,
        "required" => required,
        "optional" => optional,
        "input_schema" => schema(name),
        "result" => "FountProbe.Report v1",
        "writes_screenplay" => false
      }
    end)
  end

  def names, do: Map.keys(@catalog) |> Enum.sort()

  def schema(name) do
    {required, optional} = Map.fetch!(@catalog, name)

    properties =
      Map.new(required ++ optional, fn key ->
        s =
          cond do
            key in @lists ->
              %{"type" => "array"}

            key in @booleans ->
              %{"type" => "boolean"}

            key in @strings ->
              %{"type" => "string", "minLength" => 1}

            key in ["limit", "adjacent_scenes"] ->
              %{"type" => "integer", "minimum" => 0, "maximum" => 500}

            key == "threshold" ->
              %{"type" => "number", "minimum" => 0, "maximum" => 1}

            true ->
              %{"type" => "object"}
          end

        {key, s}
      end)

    %{
      "type" => "object",
      "properties" => properties,
      "required" => required,
      "additionalProperties" => false
    }
  end

  def validate(model, name, params) when is_map(params) do
    if Map.has_key?(@catalog, name) do
      with :ok <- Fount.Writing.Schema.validate(schema(name), params),
           :ok <- selection(model, params),
           :ok <- groups(model, params),
           :ok <- ids(model, params),
           :ok <- domain(name, params) do
        :ok
      end
    else
      {:error, :unknown_probe_tool}
    end
  end

  def validate(_, _, _), do: {:error, :invalid_probe_parameters}

  defp selection(model, %{"selection" => s}) do
    case FountProbe.Projection.selected_ids(model, s) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp selection(_, _), do: :ok

  defp groups(model, %{"comparison_groups" => groups}) do
    Enum.reduce_while(groups, {:ok, MapSet.new(), MapSet.new()}, fn
      %{"id" => id, "selection" => selection} = group, {:ok, names, used} when is_binary(id) ->
        with true <- id != "" and not MapSet.member?(names, id),
             true <- Map.keys(group) -- ~w(id selection) == [],
             {:ok, ids} <- FountProbe.Projection.selected_ids(model, selection),
             true <- MapSet.disjoint?(used, ids) do
          {:cont, {:ok, MapSet.put(names, id), MapSet.union(used, ids)}}
        else
          _ -> {:halt, {:error, :invalid_or_overlapping_comparison_groups}}
        end

      _, _ ->
        {:halt, {:error, :invalid_comparison_group}}
    end)
    |> case do
      {:ok, _, _} -> :ok
      error -> error
    end
  end

  defp groups(_, _), do: :ok

  defp ids(model, params) do
    scene_ids = Map.get(params, "scene_ids", []) ++ List.wrap(params["scene_id"])
    characters = Map.get(params, "character_ids", []) ++ List.wrap(params["character_id"])
    behavior_ids = Map.get(params, "behavior_element_ids", [])
    changed_targets = Map.get(params, "changed_targets", [])

    points =
      Map.get(params, "points", []) ++
        List.wrap(params["point"]) ++ List.wrap(params["intended_reveal_point"])

    cond do
      Enum.any?(scene_ids, &is_nil(Fount.Query.scene(model, &1))) ->
        {:error, :unknown_scene}

      Enum.any?(characters, &(not Map.has_key?(model.cast, &1))) ->
        {:error, :unknown_character}

      Enum.any?(behavior_ids, fn id ->
        case Map.get(model.index.by_id, id) do
          %Fount.IR.Element{type: type} when type in [:action, :dialogue, :parenthetical] -> false
          _ -> true
        end
      end) ->
        {:error, :unknown_behavior_element}

      Enum.any?(changed_targets, fn
        %{"kind" => "scene", "id" => id} -> is_nil(Fount.Query.scene(model, id))
        %{"kind" => "element", "id" => id} -> is_nil(Map.get(model.index.by_id, id))
        %{"kind" => "character", "id" => id} -> not Map.has_key?(model.cast, id)
        _ -> true
      end) ->
        {:error, :unknown_changed_target}

      Enum.any?(points, &(not match?({:ok, _}, FountProbe.Projection.cutoff(model, &1)))) ->
        {:error, :illegal_point}

      true ->
        :ok
    end
  end

  defp domain("search", p) do
    filters = Map.get(p, "filters", %{})

    valid =
      Map.keys(filters) --
        ~w(scene_ids character_ids character_role element_types location authored_collection_ids include_omitted include_notes include_boneyards) ==
        [] and
        Map.get(p, "mode", "retrieve") in ~w(retrieve inspect_all) and
        Map.get(filters, "character_role", "speaker") in ~w(speaker reference declared_present)

    if valid, do: :ok, else: {:error, :invalid_search_filter}
  end

  defp domain(name, p) when name in ["locate_boundary", "ablate"] do
    if p["projection"] in ~w(page_reader audience_estimate character_access) and
         (p["projection"] != "character_access" or is_binary(p["character_id"])),
       do: :ok,
       else: {:error, :invalid_projection}
  end

  defp domain("knowledge_trace", p) do
    if p["points"] != [] and p["subjects"] != [] and
         Map.get(p, "access_mode", "evidence") in ~w(evidence writer_declared),
       do: :ok,
       else: {:error, :empty_or_invalid_trace}
  end

  defp domain("continuity", p) do
    targets = Map.get(p, "changed_targets", [])

    if Enum.all?(targets, fn
         %{"kind" => kind, "id" => id}
         when kind in ~w(scene element character) and is_binary(id) ->
           true

         _ ->
           false
       end),
       do: :ok,
       else: {:error, :invalid_changed_targets}
  end

  defp domain("dialogue", p) do
    allowed = ~w(repetition exposition subtext tactic responsiveness rhythm knowledge voice)

    if p["lenses"] != [] and Enum.all?(p["lenses"], &(&1 in allowed)),
      do: :ok,
      else: {:error, :unknown_dialogue_lens}
  end

  defp domain("voice", p),
    do:
      if(length(p["character_ids"]) in 2..8,
        do: :ok,
        else: {:error, :voice_requires_two_to_eight_characters}
      )

  defp domain("scene_lift", p),
    do: if(p["scene_ids"] != [], do: :ok, else: {:error, :empty_scene_lift})

  defp domain(_, _), do: :ok
end
