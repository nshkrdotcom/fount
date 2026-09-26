defmodule FountWorkshop.Writing.Preparation do
  @moduledoc false
  alias FountWorkshop.{Store, Writing.Context}
  alias FountProbe.{Projection, Report}

  def run(model, request, services, opts \\ []) do
    with {:ok, context} <- Context.build(model, request, opts),
         {:ok, context} <- historical(context, model, request, services) do
      {requests, extra} = inspections(model, request, context)
      clients = Store.clients(services)
      report_reader = fn id -> Store.call(services[:store], :report, [id]) end

      {:ok, reports} =
        FountProbe.execute(
          model,
          requests,
          clients,
          Keyword.put_new(opts, :report_reader, report_reader)
        )

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

  @doc "Returns only inspections missing or incomplete in a saved preparation."
  def retry_requests(model, request, context) do
    {requests, _} = inspections(model, request, context)

    previous =
      (context.data["inspections"] || [])
      |> Map.new(fn report -> {get_in(report, ["provenance", "request_id"]), report} end)

    Enum.filter(requests, fn request ->
      case previous[request["id"]] do
        %{"status" => "complete"} -> false
        _ -> true
      end
    end)
  end

  def retry_failed(model, request, context, services, opts) do
    requests = retry_requests(model, request, context)

    if requests == [] do
      {:ok, context}
    else
      clients = Store.clients(services)
      report_reader = fn id -> Store.call(services[:store], :report, [id]) end

      with {:ok, reports} <-
             FountProbe.execute(
               model,
               requests,
               clients,
               Keyword.put_new(opts, :report_reader, report_reader)
             ) do
        replacements = Map.new(reports, &{&1.provenance["request_id"], Report.to_map(&1)})
        previous = context.data["inspections"] || []

        updated =
          Enum.map(previous, fn report ->
            Map.get(replacements, get_in(report, ["provenance", "request_id"]), report)
          end)

        seen = MapSet.new(updated, &get_in(&1, ["provenance", "request_id"]))

        updated =
          updated ++ for({id, report} <- replacements, not MapSet.member?(seen, id), do: report)

        {:ok,
         %{
           context
           | reports: reports,
             evidence:
               Enum.uniq_by(
                 context.evidence ++ Enum.flat_map(reports, & &1.evidence),
                 & &1["evidence_id"]
               ),
             data: Map.put(context.data, "inspections", updated)
         }}
      end
    end
  end

  defp inspections(_, %{"workflow" => "develop", "options" => opts}, _context) do
    {[],
     %{
       "development_brief" => opts["brief"],
       "entry_requirements" => opts["entry_requirements"] || [],
       "exit_requirements" => opts["exit_requirements"] || [],
       "placement" => opts["placement"]
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

  defp inspections(_, %{"workflow" => "propagate", "options" => opts} = request, context) do
    targets = propagation_targets(request)

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

    conflicts = FountWorkshop.Writing.NoteConflicts.detect(model, notes ++ external)

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
    source_screenplay_id = Map.get(opts, "source_screenplay_id", model.id)

    with {:ok, source} <-
           Store.call(services[:store], :load_revision, [
             source_screenplay_id,
             opts["source_revision_id"]
           ]),
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
          "screenplay_id" => source.id,
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
          "speaker_links" =>
            source.mentions
            |> Map.values()
            |> Enum.filter(&(&1.role == :speaker_cue and &1.status == :confirmed))
            |> Map.new(&{&1.element_id, &1.character_id}),
          "cast" => Fount.Screenplay.Model.plain(Map.values(source.cast))
        })

      {:ok,
       Map.merge(context, %{
         data: data,
         restore_registry: registry,
         source_models: if(source.id == model.id, do: [model, source], else: [model]),
         historical_models: [source],
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

    probe_opts =
      Keyword.put_new(opts, :report_reader, fn id ->
        Store.call(services[:store], :report, [id])
      end)

    followup_limit = max(0, Keyword.get(opts, :max_investigation_followups, 1))

    with {:ok, plan} <-
           FountProbe.plan(
             model,
             concern,
             clients,
             Keyword.put(probe_opts, :selection, context.selection)
           ),
         {:ok, reports} <- FountProbe.execute(model, plan.data["requests"], clients, probe_opts),
         {:ok, first_explanation} <-
           FountProbe.explain(
             model,
             concern,
             reports,
             clients,
             probe_opts
             |> Keyword.put(:hypotheses, plan.data["hypotheses"])
             |> Keyword.put(:followups_remaining, if(followup_limit > 0, do: 3, else: 0))
           ),
         {:ok, followup_reports, explanation} <-
           investigation_followup(
             model,
             concern,
             plan,
             reports,
             first_explanation,
             clients,
             probe_opts,
             followup_limit
           ) do
      all =
        [plan | reports] ++
          [first_explanation] ++
          followup_reports ++
          if(explanation.id == first_explanation.id, do: [], else: [explanation])

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
             |> Map.put(
               "investigation_followup_count",
               if(followup_reports == [], do: 0, else: 1)
             )
       }
       |> Map.put(:investigation_strategies, explanation.data["strategies"])}
    end
  end

  @doc false
  def propagation_targets(request) do
    constraint_targets =
      Enum.flat_map(request["constraints"] || [], fn constraint ->
        [constraint["target"], get_in(constraint, ["spec", "at"])]
      end)

    destination =
      for id <- get_in(request, ["options", "destination", "scene_ids"]) || [],
          do: %{"kind" => "scene", "id" => id}

    (constraint_targets ++ destination)
    |> Enum.filter(&is_map/1)
    |> Enum.reject(&(&1["kind"] == "screenplay"))
    |> Enum.uniq()
  end

  defp investigation_followup(_, _, _, _, explanation, _, _, 0),
    do: {:ok, [], explanation}

  defp investigation_followup(model, concern, plan, reports, explanation, clients, opts, _) do
    requests = explanation.data["follow_up_requests"] || []
    initial_ids = MapSet.new(plan.data["requests"], & &1["id"])

    cond do
      requests == [] ->
        {:ok, [], explanation}

      Enum.any?(requests, &MapSet.member?(initial_ids, &1["id"])) ->
        {:error, :duplicate_investigation_request_id}

      true ->
        with {:ok, followup_reports} <- FountProbe.execute(model, requests, clients, opts),
             {:ok, revised} <-
               FountProbe.explain(
                 model,
                 concern,
                 reports ++ followup_reports,
                 clients,
                 opts
                 |> Keyword.put(:hypotheses, explanation.data["revised_hypotheses"])
                 |> Keyword.put(:followups_remaining, 0)
               ) do
          {:ok, followup_reports, revised}
        end
    end
  end
end
