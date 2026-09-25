defmodule FountWorkshop.Writing.Preparation do
  @moduledoc false
  alias FountWorkshop.{Store, Writing.Context}
  alias FountProbe.{Projection, Report}

  def run(model, request, services, opts \\ []) do
    with {:ok, context} <- Context.build(model, request, opts),
         {:ok, context} <- historical(context, model, request, services) do
      {requests, extra} = inspections(model, request, context)
      clients = Store.clients(services)
      {:ok, reports} = FountProbe.execute(model, requests, clients, opts)

      evidence =
        Enum.uniq_by(
          context.evidence ++ Enum.flat_map(reports, & &1.evidence),
          & &1["evidence_id"]
        )

      context = %{
        context
        | evidence: evidence,
          data:
            Map.merge(context.data, extra)
            |> Map.put("inspections", Enum.map(reports, &Report.to_map/1))
      }

      context = Map.put(context, :reports, reports)

      if request["workflow"] == "investigate",
        do: investigate(model, request, context, services, opts),
        else: {:ok, context}
    end
  end

  defp inspections(_, %{"workflow" => "develop", "options" => opts}, context) do
    {[],
     %{
       "development_brief" => opts["brief"],
       "entry_requirements" => opts["entry_requirements"] || [],
       "exit_requirements" => opts["exit_requirements"] || [],
       "placement" => opts["placement"],
       "known_neighbor_pages" => context.data["selected_pages"]
     }}
  end

  defp inspections(_, %{"workflow" => "alternatives", "options" => opts}, context) do
    {[
       request("mechanics", "scene_mechanics", %{
         "selection" => context.selection,
         "concern" => "Find distinct choices or sources of resistance available in these pages."
       })
     ], %{"writer_approaches" => opts["approaches"] || []}}
  end

  defp inspections(_, %{"workflow" => "propagate", "options" => opts}, context) do
    targets =
      case context.selection do
        %{"targets" => targets} -> targets
        _ -> []
      end

    {[
       request("dependencies", "dependencies", %{
         "selection" => context.selection,
         "targets" => targets,
         "include_alternative_support" => true,
         "inspect_setup_purpose" => true
       }),
       request("continuity", "continuity", %{"selection" => context.selection})
     ],
     %{
       "story_change" => opts["change"],
       "destination" => opts["destination"],
       "required_grouping" =>
         "The primary story change and every consequence repair form explicit groups. Each dependent repair names the primary group. Preserve all named motivations, secrets, object transfers and later payoffs."
     }}
  end

  defp inspections(_, %{"workflow" => "sequence", "options" => opts}, context) do
    {[
       request("sequence-functions", "scene_mechanics", %{
         "selection" => context.selection,
         "include_tactics" => true
       }),
       request("setup-payoff", "dependencies", %{
         "selection" => context.selection,
         "targets" => [],
         "include_alternative_support" => true
       })
     ],
     %{
       "target_scene_count" => opts["target_scene_count"],
       "requested_page_reduction" => opts["page_reduction"],
       "entry_requirements" => opts["entry_requirements"] || [],
       "exit_requirements" => opts["exit_requirements"] || [],
       "sequence_direction" =>
         "Rebuild causal action, not five scenes abbreviated into three headings. Alternatives must take meaningfully different routes."
     }}
  end

  defp inspections(model, %{"workflow" => "character", "options" => opts}, context) do
    id = opts["character_id"]

    requests = [
      request("character-dialogue", "dialogue", %{
        "selection" => context.selection,
        "lenses" => ~w(subtext responsiveness knowledge),
        "character_ids" => [id]
      }),
      request("character-agency", "scene_mechanics", %{
        "selection" => context.selection,
        "character_id" => id,
        "concern" => opts["direction"],
        "include_tactics" => true
      })
    ]

    cast_ids =
      [id | Enum.reject(Map.keys(model.cast) |> Enum.sort(), &(&1 == id))] |> Enum.take(8)

    requests =
      if length(cast_ids) >= 2,
        do:
          requests ++
            [
              request("voice", "voice", %{
                "selection" => %{"whole_screenplay" => true},
                "character_ids" => cast_ids
              })
            ],
        else: requests

    {requests,
     %{
       "character_workspace" => %{
         "character_id" => id,
         "direction" => opts["direction"],
         "exemplar_targets" => opts["exemplar_targets"] || [],
         "change_agency" => Map.get(opts, "change_agency", false)
       },
       "partner_rule" =>
         "Revise the character's action, tactics and speech across the workspace, not a generic dialect substitution. Repair partner responses where necessary. Preserve chosen outcomes and secret-access constraints. Other characters' established voices remain distinct."
     }}
  end

  defp inspections(model, %{"workflow" => "notes", "options" => opts}, context) do
    notes = Enum.map(Map.get(opts, "note_ids", []), &model.authored_items[&1])

    external =
      Enum.map(Enum.with_index(Map.get(opts, "external_notes", [])), fn {note, i} ->
        %{
          "id" =>
            Fount.ID.v5(model.id, [
              "external-note:",
              model.revision.id,
              ":",
              Integer.to_string(i),
              ":",
              Jason.encode!(note)
            ]),
          "kind" => "note",
          "source" => "request",
          "value" => note
        }
      end)

    conflicts =
      for {a, i} <- Enum.with_index(notes ++ external),
          {b, j} <- Enum.with_index(notes ++ external),
          i < j,
          a["target"] && a["target"] == b["target"],
          do: %{
            "note_ids" => [a["id"], b["id"]],
            "status" => "potential_conflict",
            "instructions" => [a["value"], b["value"]]
          }

    {[
       request("note-context", "scene_mechanics", %{
         "selection" => context.selection,
         "concern" =>
           "Locate scene and sequence functions implicated by the supplied writer notes."
       })
     ],
     %{
       "notes" => notes ++ external,
       "note_conflicts" => conflicts,
       "note_grouping_rule" =>
         "Separate independent local and sequence notes into selectable groups, give causal dependencies, cite addresses_notes IDs, and expose conflicting instructions rather than claiming both satisfied. External notes remain request records, not silently created or resolved authored items."
     }}
  end

  defp inspections(_, %{"workflow" => "pass", "options" => opts}, context) do
    profile =
      File.read!(
        Application.app_dir(:fount_workshop, "priv/writing_profiles/#{opts["profile"]}.json")
      )
      |> Jason.decode!()

    requests =
      case opts["profile"] do
        "dialogue_subtext" ->
          [
            request("dialogue", "dialogue", %{
              "selection" => context.selection,
              "lenses" => ~w(subtext exposition responsiveness)
            })
          ]

        "action_visual" ->
          [
            request("action", "action", %{
              "selection" => context.selection,
              "direction" => opts["direction"] || profile["goal"]
            })
          ]

        "brevity" ->
          [
            request("rhythm", "dialogue", %{
              "selection" => context.selection,
              "lenses" => ~w(repetition rhythm)
            }),
            request("function", "scene_mechanics", %{"selection" => context.selection})
          ]

        "dry_comedy" ->
          [
            request("comedy-dialogue", "dialogue", %{
              "selection" => context.selection,
              "lenses" => ~w(subtext tactic responsiveness)
            }),
            request("comedy-action", "action", %{"selection" => context.selection})
          ]

        "tension" ->
          [
            request("tension-functions", "scene_mechanics", %{
              "selection" => context.selection,
              "concern" =>
                "Sources of resistance, stakes, uncertainty, reversals and meaningful character choice. Silence and direct conflict are both possible."
            })
          ]

        "custom" ->
          [
            request("custom-mechanics", "scene_mechanics", %{
              "selection" => context.selection,
              "concern" => opts["direction"]
            })
          ]
      end

    {requests,
     %{
       "pass_profile" => profile,
       "writer_direction" => opts["direction"],
       "pass_rule" =>
         "Write revised pages in selective groups. The profile is a lens, not universal rules. Preserve intentional long turns, direct emotion and existing good material when they serve the writer's direction."
     }}
  end

  defp inspections(_, %{"workflow" => "recover"}, _),
    do:
      {[],
       %{
         "recovery_rule" =>
           "Compare source/current/proposed pages. Adapt dramatic function only when requested; label copied versus generated groups and preserve exact selected historical language where pinned."
       }}

  defp inspections(_, %{"workflow" => "investigate"}, _), do: {[], %{}}
  defp request(id, tool, params), do: %{"id" => id, "tool" => tool, "params" => params}

  defp historical(context, model, %{"workflow" => "recover", "options" => opts}, services) do
    with {:ok, source} <-
           Store.call(services[:store], :load_revision, [model.id, opts["source_revision_id"]]),
         {:ok, units} <-
           Projection.select(source, %{"targets" => opts["source_targets"]},
             include_omitted: true,
             include_notes: true,
             include_boneyards: true
           ) do
      registry =
        Map.new(
          source.ir.elements ++
            source.ir.scenes ++ source.ir.dialogue_blocks ++ Map.values(source.cast),
          &{&1.id, &1}
        )

      data =
        context.data
        |> Map.put("historical_source", %{
          "revision_id" => source.revision.id,
          "targets" => opts["source_targets"],
          "pages" => units,
          "scene_specs" =>
            Enum.map(
              Enum.filter(source.ir.scenes, fn s ->
                Enum.any?(opts["source_targets"], &(&1["kind"] == "scene" and &1["id"] == s.id))
              end),
              &scene_spec(source, &1)
            ),
          "cast" => Fount.Screenplay.Model.plain(Map.values(source.cast))
        })

      {:ok,
       Map.merge(context, %{
         data: data,
         restore_registry: registry,
         source_models: [model, source],
         evidence:
           Enum.uniq_by(context.evidence ++ Projection.evidence(units), & &1["evidence_id"])
       })}
    end
  end

  defp historical(context, _, _, _), do: {:ok, context}

  defp scene_spec(model, scene),
    do: %{
      "id" => scene.id,
      "heading" => Fount.Query.node(model, scene.heading_id).text,
      "number" => scene.number,
      "omitted" => scene.omitted?,
      "elements" =>
        Enum.map(Enum.reject(scene.element_ids, &(&1 == scene.heading_id)), &%{"keep" => &1})
    }

  defp investigate(model, request, context, services, opts) do
    concern = request["options"]["concern"] || request["instruction"]
    clients = Store.clients(services)

    with {:ok, plan} <-
           FountProbe.plan(
             model,
             concern,
             clients,
             Keyword.put(opts, :selection, context.selection)
           ),
         {:ok, reports} <- FountProbe.execute(model, plan.data["requests"], clients, opts),
         {:ok, explanation} <-
           FountProbe.explain(
             model,
             concern,
             reports,
             clients,
             Keyword.put(opts, :hypotheses, plan.data["hypotheses"])
           ) do
      all = [plan | reports] ++ [explanation]

      {:ok,
       %{
         context
         | reports: context.reports ++ all,
           evidence:
             Enum.uniq_by(
               context.evidence ++ Enum.flat_map(all, & &1.evidence),
               & &1["evidence_id"]
             ),
           data:
             context.data
             |> Map.put("investigation", explanation.data)
             |> Map.put("initial_hypotheses", plan.data["hypotheses"])
       }
       |> Map.put(:investigation_strategies, explanation.data["strategies"])}
    end
  end
end
