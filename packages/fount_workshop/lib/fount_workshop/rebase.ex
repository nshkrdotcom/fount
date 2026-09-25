defmodule FountWorkshop.Rebase do
  @moduledoc "Explicit three-way rebase. Disjoint edits replay; conflicts expose concrete source/current/candidate passages."
  alias FountWorkshop.{Store, Candidate, CandidateAPI}
  alias FountWorkshop.Writing.{Footprint, ChangeGroups}

  def run(id, current, resolutions, services, opts \\ []) do
    with :ok <- validate_resolutions(resolutions),
         {:ok, candidate} <- Store.call(services[:store], :candidate, [id]),
         true <- current.id == candidate["screenplay_id"] or {:error, :different_screenplay},
         {:ok, base} <-
           Store.call(services[:store], :load_revision, [
             current.id,
             candidate["base_revision_id"]
           ]) do
      groups = Candidate.proposal(candidate)["groups"]
      conflicts = conflicts(base, current, candidate, groups)
      choices = Map.get(resolutions, "choices", %{})
      unresolved = Enum.reject(conflicts, &Map.has_key?(choices, &1["group_id"]))
      conflict_ids = MapSet.new(conflicts, & &1["group_id"])

      cond do
        resolutions["generate"] == true ->
          generate(current, candidate, conflicts, resolutions, services, opts)

        Enum.any?(choices, fn {group, _} -> not MapSet.member?(conflict_ids, group) end) ->
          {:error, :invalid_rebase_choice}

        unresolved != [] ->
          {:error, {:rebase_conflicts, unresolved}}

        true ->
          ids = for g <- groups, choices[g["id"]] != "current", do: g["id"]

          if ids == [],
            do: {:ok, %{"status" => "no_change", "kept_revision_id" => current.revision.id}},
            else: deterministic(current, candidate, ids, services, opts)
      end
    end
  end

  def validate_resolutions(resolutions) when is_map(resolutions) do
    choices = Map.get(resolutions, "choices", %{})
    generate = Map.get(resolutions, "generate", false)

    if Map.keys(resolutions) -- ~w(choices generate request) == [] and
         is_map(choices) and
         Enum.all?(choices, fn {id, choice} ->
           is_binary(id) and id != "" and choice in ["current", "candidate"]
         end) and
         is_boolean(generate) and
         (not generate or is_map(resolutions["request"])) and
         (generate or is_nil(resolutions["request"])),
       do: :ok,
       else: {:error, :invalid_rebase_resolution}
  end

  def validate_resolutions(_), do: {:error, :invalid_rebase_resolution}

  def conflicts(base, current, candidate, groups) do
    Enum.flat_map(groups, fn g ->
      surfaces = Enum.flat_map(g["operations"], &Footprint.operation(base, &1))

      changed =
        Enum.filter(surfaces, fn {kind, id, _span} ->
          surface(base, kind, id) != surface(current, kind, id)
        end)

      if changed == [],
        do: [],
        else: [
          %{
            "group_id" => g["id"],
            "surfaces" =>
              Enum.map(changed, fn {kind, id, span} ->
                %{
                  "kind" => kind,
                  "id" => Fount.Screenplay.Model.plain(id),
                  "span" => span,
                  "base" => surface(base, kind, id),
                  "current" => surface(current, kind, id),
                  "candidate" => surface(candidate["screenplay"], kind, id)
                }
              end)
          }
        ]
    end)
  end

  defp deterministic(current, candidate, ids, services, opts) do
    p = Candidate.proposal(candidate)

    with {:ok, groups} <- ChangeGroups.select(p["groups"], ids),
         proposal =
           p |> Map.put("base_revision_id", current.revision.id) |> Map.put("groups", groups),
         {:ok, rebased} <-
           Candidate.compile(
             current,
             proposal,
             opts
             |> Keyword.put(:writer_edit, true)
             |> Keyword.put(:reference_map, candidate["provenance"]["allocated_ids"] || %{})
             |> Keyword.put(:evidence, candidate["provenance"]["evidence"] || [])
             |> Keyword.put(:constraints, candidate["provenance"]["constraints"] || [])
             |> Keyword.put(:lineage, [
               %{
                 "candidate_id" => candidate["id"],
                 "operation" => "three_way_rebase",
                 "old_base_revision_id" => candidate["base_revision_id"]
               }
             ])
           ),
         request = %{
           "version" => 1,
           "workflow" => "alternatives",
           "mode" => "revise",
           "base_revision_id" => current.revision.id,
           "instruction" => "Writer-approved three-way rebase",
           "selection" => %{"whole_screenplay" => true},
           "constraints" => rebased["provenance"]["constraints"],
           "alternatives" => 1,
           "options" => %{"candidate_ids" => [candidate["id"]]}
         },
         {:ok, session} <-
           Store.call(services[:store], :save_session, [
             %{
               "id" => Fount.ID.v4(),
               "screenplay_id" => current.id,
               "base_revision_id" => current.revision.id,
               "workflow" => "alternatives",
               "request" => request,
               "status" => "review_ready",
               "strategies" => [],
               "progress" => %{},
               "provenance" => %{"operation" => "deterministic_rebase"}
             }
           ]) do
      CandidateAPI.save_checked(current, rebased, session["id"], services, opts)
    end
  end

  defp generate(current, candidate, conflicts, resolutions, services, opts) do
    case resolutions["request"] do
      %{} = request ->
        FountWorkshop.Session.start(
          current,
          Map.put(request, "base_revision_id", current.revision.id),
          services,
          Keyword.put(opts, :rebase_context, %{
            "source_candidate_id" => candidate["id"],
            "conflicts" => conflicts,
            "source_pages" => Fount.Screenplay.to_fountain(candidate["screenplay"])
          })
        )

      _ ->
        {:error, :semantic_rebase_requires_explicit_new_writing_request}
    end
  end

  defp surface(model, "element", id) do
    case Fount.Query.node(model, id) do
      nil -> nil
      e -> Fount.Screenplay.Model.plain(Map.take(e, [:id, :type, :text, :attrs]))
    end
  end

  defp surface(model, "scene", id) do
    case Fount.Query.scene(model, id) do
      nil ->
        nil

      s ->
        %{
          "id" => s.id,
          "element_ids" => s.element_ids,
          "position" => Enum.find_index(model.ir.scenes, &(&1.id == id))
        }
    end
  end

  defp surface(model, "scene_gap", id),
    do: %{"after" => id, "order" => Enum.map(model.ir.scenes, & &1.id)}

  defp surface(model, "element_gap", {owner, position, anchor}),
    do: %{
      "owner" => owner,
      "position" => position,
      "anchor" => surface(model, "element", anchor),
      "scene" => surface(model, "scene", owner)
    }

  defp surface(model, "character", id), do: Fount.Screenplay.Model.plain(model.cast[id])
  defp surface(model, "title", _), do: Fount.Screenplay.Model.plain(model.ir.title_page)
  defp surface(model, "put_character", id), do: Fount.Screenplay.Model.plain(model.cast[id])
  defp surface(model, "put_authored_item", id), do: model.authored_items[id]

  defp surface(model, kind, id) do
    case Fount.Target.resolve(model, %{"kind" => kind, "id" => id}) do
      {:ok, value} -> Fount.Screenplay.Model.plain(value)
      _ -> nil
    end
  end
end
