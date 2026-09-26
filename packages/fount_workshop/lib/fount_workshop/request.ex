defmodule FountWorkshop.Request do
  @moduledoc "Closed writer request validation before persistence or paid calls."
  alias Fount.Writing.Schema
  alias Fount.Writing.UTF8Span

  @options %{
    "develop" =>
      ~w(placement brief brief_item_id story_plan_id entry_requirements exit_requirements),
    "alternatives" => ~w(strategy_ids approaches candidate_ids),
    "propagate" => ~w(change destination repair_scope),
    "sequence" => ~w(target_scene_count page_reduction entry_requirements exit_requirements),
    "character" => ~w(character_id direction exemplar_targets change_agency),
    "notes" => ~w(note_ids external_notes),
    "pass" => ~w(profile direction),
    "recover" =>
      ~w(source_revision_id source_screenplay_id source_targets destination cast_mapping adapt),
    "investigate" => ~w(concern write_fixes)
  }
  def validate(model, request) when is_map(request) do
    workflow = request["workflow"]

    request =
      request
      |> Map.put_new("version", 1)
      |> Map.put_new("mode", "revise")
      |> Map.put_new("constraints", [])
      |> Map.put_new("options", %{})
      |> Map.put_new("alternatives", default_alternatives(request))

    with :ok <- Schema.validate("workflow.schema.json", request),
         true <-
           request["base_revision_id"] == model.revision.id or {:error, :request_base_mismatch},
         true <-
           Map.keys(request["options"]) -- Map.get(@options, workflow, []) == [] or
             {:error, :unknown_workflow_option},
         {:ok, _} <- FountProbe.Projection.selected_ids(model, request["selection"]),
         {:ok, constraints} <- FountProbe.Constraints.resolve(model, request["constraints"]),
         :ok <- options(model, workflow, request["options"]) do
      {:ok, Map.put(request, "constraints", constraints)}
    end
  end

  def validate(_, _), do: {:error, :invalid_request}
  defp default_alternatives(%{"mode" => "explore"}), do: 3
  defp default_alternatives(%{"workflow" => "pass"}), do: 1
  defp default_alternatives(_), do: 2

  defp options(model, "develop", opts) do
    if opts["brief"] && opts["brief_item_id"],
      do: {:error, :brief_and_brief_item_are_exclusive},
      else: placement(model, Map.get(opts, "placement", %{"kind" => "start"}))
  end

  defp options(model, "recover", opts) do
    source_screenplay_id = Map.get(opts, "source_screenplay_id", model.id)
    foreign? = source_screenplay_id != model.id
    mapping = opts["cast_mapping"]

    with true <- is_binary(opts["source_revision_id"]) or {:error, :missing_source_revision},
         true <- is_binary(source_screenplay_id) or {:error, :invalid_source_screenplay},
         true <-
           (is_list(opts["source_targets"]) and opts["source_targets"] != []) or
             {:error, :missing_source_targets},
         true <- not foreign? or is_map(mapping) or {:error, :explicit_cast_mapping_required},
         true <-
           not foreign? or
             Enum.all?(mapping, fn {_, id} -> Map.has_key?(model.cast, id) end) or
             {:error, :unknown_cast_mapping_destination} do
      placement(model, opts["destination"])
    end
  end

  defp options(_, "sequence", opts) do
    if is_integer(opts["target_scene_count"]) and opts["target_scene_count"] > 0,
      do: :ok,
      else: {:error, :invalid_target_scene_count}
  end

  defp options(model, "character", opts) do
    if Map.has_key?(model.cast, opts["character_id"]) and is_binary(opts["direction"]),
      do: :ok,
      else: {:error, :invalid_character_direction}
  end

  defp options(model, "notes", opts) do
    ids = Map.get(opts, "note_ids", [])

    if is_list(ids) and
         Enum.all?(ids, &(model.authored_items[&1] && model.authored_items[&1]["kind"] == "note")) and
         is_list(Map.get(opts, "external_notes", [])), do: :ok, else: {:error, :invalid_notes}
  end

  defp options(_, "pass", opts) do
    if opts["profile"] in ~w(dialogue_subtext action_visual brevity dry_comedy tension custom) and
         (opts["profile"] != "custom" or
            (is_binary(opts["direction"]) and String.trim(opts["direction"]) != "")),
       do: :ok,
       else: {:error, :invalid_pass_profile}
  end

  defp options(model, "propagate", opts) do
    with true <-
           (is_binary(opts["change"]) and opts["change"] != "") or {:error, :missing_story_change},
         {:ok, _} <-
           FountProbe.Projection.selected_ids(
             model,
             Map.get(opts, "repair_scope", %{"whole_screenplay" => true})
           ) do
      :ok
    end
  end

  defp options(_, _, _), do: :ok
  def placement(_model, %{"kind" => "start"} = p), do: only(p, ~w(kind))

  def placement(model, %{"kind" => "after_scene", "after_scene_id" => id} = p) do
    with :ok <- only(p, ~w(kind after_scene_id)),
         true <- not is_nil(Fount.Query.scene(model, id)) or {:error, :unknown_scene} do
      :ok
    end
  end

  def placement(
        model,
        %{"kind" => "between_scenes", "after_scene_id" => left, "before_scene_id" => right} = p
      ) do
    ids = Enum.map(model.ir.scenes, & &1.id)

    with :ok <- only(p, ~w(kind after_scene_id before_scene_id)),
         true <- Enum.chunk_every(ids, 2, 1, :discard) |> Enum.member?([left, right]) do
      :ok
    else
      false -> {:error, :neighbors_not_adjacent}
      error -> error
    end
  end

  def placement(model, %{"kind" => "replace_range", "scene_ids" => ids} = p)
      when is_list(ids) and ids != [] do
    order = Enum.map(model.ir.scenes, & &1.id)

    with :ok <- only(p, ~w(kind scene_ids)),
         true <- Enum.chunk_every(order, length(ids), 1, :discard) |> Enum.member?(ids) do
      :ok
    else
      false -> {:error, :noncontiguous_scene_range}
      error -> error
    end
  end

  def placement(model, %{"kind" => "replace_note", "note_id" => id} = p) do
    with :ok <- only(p, ~w(kind note_id)), %{type: :note} <- Fount.Query.node(model, id) do
      :ok
    else
      _ -> {:error, :unknown_fountain_note}
    end
  end

  def placement(
        model,
        %{
          "kind" => "replace_element_span",
          "element_id" => id,
          "span" => %{"byte_start" => first, "byte_end" => last}
        } = p
      ) do
    with :ok <- only(p, ~w(kind element_id span)),
         element when not is_nil(element) <- Fount.Query.node(model, id),
         {:ok, _} <- UTF8Span.extract(element.text, {first, last}) do
      :ok
    else
      _ -> {:error, :invalid_recovery_destination_span}
    end
  end

  def placement(model, %{"kind" => "insert_after_element", "element_id" => id} = p) do
    with :ok <- only(p, ~w(kind element_id)),
         element when not is_nil(element) <- Fount.Query.node(model, id),
         true <- element.type != :scene_heading and not is_nil(Fount.Query.scene_for(model, id)) do
      :ok
    else
      _ -> {:error, :invalid_recovery_anchor}
    end
  end

  def placement(_, _), do: {:error, :invalid_placement}

  defp only(p, keys),
    do: if(Map.keys(p) -- keys == [], do: :ok, else: {:error, :unknown_placement_field})
end
