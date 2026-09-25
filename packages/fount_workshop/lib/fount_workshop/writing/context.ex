defmodule FountWorkshop.Writing.Context do
  @moduledoc false
  alias FountProbe.Projection
  def build(model, request, opts \\ []) do
    selection = editable_selection(model, request)
    with {:ok, selected} <- Projection.select(model, selection), {:ok, all} <- Projection.select(model, %{"whole_screenplay" => true}) do
      selected_scenes = selected |> Enum.map(& &1["scene_id"]) |> Enum.reject(&is_nil/1) |> Enum.uniq()
      scene_ids = Enum.map(model.ir.scenes, & &1.id)
      context_ids = selected_scenes |> Enum.flat_map(fn id -> i = Enum.find_index(scene_ids, &(&1 == id)); Enum.slice(scene_ids, max(i - 1, 0), if(i == 0, do: 2, else: 3)) end) |> Enum.uniq()
      context = Enum.filter(all, &(&1["scene_id"] in context_ids))
      # Creative writing may use the whole story. Knowledge tools use independent access-limited projections.
      data = %{"screenplay_id" => model.id, "base_revision_id" => model.revision.id,
        "request" => request, "editable_selection" => selection, "selected_pages" => selected,
        "adjacent_read_only_pages" => Enum.reject(context, &(&1["evidence_id"] in Enum.map(selected, fn u -> u["evidence_id"] end))),
        "scene_index" => Enum.map(model.ir.scenes, fn s -> %{"id" => s.id, "heading_id" => s.heading_id,
          "heading" => Fount.Query.node(model, s.heading_id).text, "element_ids" => s.element_ids, "omitted" => s.omitted?} end),
        "dialogue_blocks" => Fount.Screenplay.Model.plain(model.ir.dialogue_blocks),
        "confirmed_cast" => Fount.Screenplay.Model.plain(Map.values(model.cast)),
        "confirmed_mentions" => Fount.Screenplay.Model.plain(Enum.filter(Map.values(model.mentions), &(&1.status == :confirmed))),
        "writer_authored_items" => Map.values(model.authored_items),
        "rebase_context" => Keyword.get(opts, :rebase_context),
        "scope_notice" => "Only selected pages may change. Adjacent material informs joins, not permission to rewrite it. Actor utterances are not automatically facts."}
      if byte_size(Jason.encode!(data)) > Keyword.get(opts, :max_context_bytes, 100_000), do: {:error, :context_limit_requires_smaller_selection},
        else: {:ok, %{data: data, selection: selection, evidence: Projection.evidence(Enum.uniq_by(selected ++ context, & &1["evidence_id"])), source_models: [model]}}
    end
  end
  def editable_selection(model, %{"workflow" => "character", "options" => %{"character_id" => id}}) do
    ids = Fount.Query.character_dialogue(model, id) |> Enum.flat_map(&[&1.cue_id | &1.body_ids])
    ids = ids ++ Enum.map(Fount.Query.character_mentions(model, id), & &1.element_id)
    scenes = ids |> Enum.map(&Fount.Query.scene_for(model, &1)) |> Enum.reject(&is_nil/1) |> Enum.uniq_by(& &1.id)
    if scenes == [], do: %{"targets" => [%{"kind" => "character", "id" => id}]}, else: %{"targets" => Enum.map(scenes, &%{"kind" => "scene", "id" => &1.id})}
  end
  def editable_selection(_, %{"workflow" => "propagate", "options" => opts, "selection" => selection}), do: Map.get(opts, "repair_scope", selection)
  def editable_selection(_, request), do: request["selection"]

  def compile_options(model, request, context, opts) do
    options = request["options"]
    result = opts |> Keyword.put(:evidence, context.evidence) |> Keyword.put(:constraints, request["constraints"])
      |> Keyword.put(:editable_selection, context.selection) |> Keyword.put(:restore_registry, Map.get(context, :restore_registry, %{}))
    result = if request["workflow"] == "develop", do: Keyword.put(result, :placement, options["placement"]), else: result
    if request["workflow"] == "sequence" do
      {:ok, units} = Projection.select(model, context.selection)
      ids = units |> Enum.map(& &1["scene_id"]) |> Enum.reject(&is_nil/1) |> Enum.uniq()
      result |> Keyword.put(:target_scene_count, options["target_scene_count"]) |> Keyword.put(:sequence_scene_ids, ids)
    else result end
  end
end
