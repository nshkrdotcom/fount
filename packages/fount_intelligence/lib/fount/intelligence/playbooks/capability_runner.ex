defmodule Fount.Intelligence.Playbooks.CapabilityRunner do
  @moduledoc "Capability shell through Phase 7: exact screenplay selection -> validated Observe measurements -> pure reasoning -> optional writer packet."

  alias Fount.Intelligence.Acquisition.{CapabilityMeasurements, ContextBuilder, Measurements}
  alias Fount.Intelligence.Capabilities
  alias Fount.Intelligence.Capabilities.Result
  alias Fount.Intelligence.Playbooks.WriterRegistry
  alias Fount.Intelligence.Reader
  alias Fount.Intelligence.Reporting.WriterPacket
  alias Fount.Intelligence.Runner.Resources
  alias Fount.Intelligence.StoryWorld
  alias Fount.Screenplay.Model

  @default_provider_cap 240
  @default_scene_cap 160
  @default_fragments_per_scene 32

  @playbook_families %{
    "scene_doctor" => ~w(scene_engine),
    "character_trajectory" => ~w(character_trajectory agency_causality),
    "relationship_pass" => ~w(relationship_dynamics),
    "suspense_audit" => ~w(audience_reader_experience),
    "sequence_momentum" => ~w(sequence_movement),
    "dialogue_pass" => ~w(dialogue_interaction relationship_dynamics),
    "setup_payoff" => ~w(setup_payoff_motifs)
  }

  def playbook_families, do: @playbook_families

  def preflight(model, family, request, opts \\ []) do
    with {:ok, prepared} <- prepare(model, family, request, opts),
         {:ok, cap} <- provider_cap(opts),
         {:ok, estimate} <-
           Measurements.preflight(
             prepared.inputs,
             prepared.spec["questions"],
             measurement_opts(
               opts,
               model,
               prepared.spec["lens_id"],
               min(cap, length(prepared.inputs))
             )
           ) do
      {:ok,
       %{
         "family" => family,
         "source_revision" => model.revision.id,
         "subject" => Model.plain(prepared.subject),
         "selection" => prepared.selection,
         "coverage" => prepared.coverage,
         "estimate" => estimate,
         "story_world_record_count" => length(prepared.records),
         "limitations" => [
           "Preflight dispatches no provider request and reports no hosted-cost estimate unless a runtime can supply one.",
           "StoryWorld records are caller-supplied frozen derived data; absent records remain unknown rather than being invented."
         ]
       }}
    end
  end

  def run(model, family, request, clients \\ %{}, opts \\ []) do
    with {:ok, provider} <- provider(clients),
         {:ok, prepared} <- prepare(model, family, request, opts),
         {:ok, cap} <- provider_cap(opts),
         {:ok, report} <-
           Measurements.evaluate(
             provider,
             prepared.inputs,
             prepared.spec["questions"],
             measurement_opts(
               opts,
               model,
               prepared.spec["lens_id"],
               min(cap, length(prepared.inputs))
             )
           ),
         entries = annotate_entries(report["entries"], prepared.inputs),
         {:ok, result} <-
           Capabilities.analyze(
             family,
             prepared.world,
             prepared.subject,
             entries,
             intent: prepared.intent,
             reader: prepared.reader
           ) do
      result =
        %{
          result
          | status: combined_status(result.status, report["status"], prepared.coverage),
            metadata:
              Map.merge(result.metadata, %{
                "measurement_spec_sha256" => report["measurement_spec_sha256"],
                "measurement_spec" => report["measurement_spec"],
                "measurement_resource_usage" => report["resource_usage"],
                "measurement_errors" => report["errors"],
                "selection_coverage" => prepared.coverage,
                "story_world_record_count" => length(prepared.records)
              })
        }

      {:ok, result}
    end
  rescue
    _ in [ArgumentError, KeyError, FunctionClauseError, MatchError, BadMapError] ->
      {:error, :invalid_capability_request}
  end

  def preflight_playbook(model, playbook, request, opts \\ []) do
    with {:ok, families} <- families_for_playbook(playbook) do
      preflight_families(model, playbook, request, opts, families)
    end
  end

  defp preflight_families(model, playbook, request, opts, families) do
    Enum.reduce_while(families, {:ok, []}, fn family, {:ok, acc} ->
      case preflight(model, family, request, opts) do
        {:ok, result} -> {:cont, {:ok, acc ++ [result]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, %{"playbook" => playbook, "families" => results}}
      error -> error
    end
  end

  def run_playbook(model, playbook, request, clients \\ %{}, opts \\ []) do
    with {:ok, definition} <- WriterRegistry.fetch(playbook),
         {:ok, families} <- families_for_playbook(playbook),
         {:ok, results} <- run_families(model, families, request, clients, shared_budget(opts)) do
      packet(model, definition, request, results)
    end
  end

  defp prepare(model, family, request, opts) when is_map(request) do
    with {:ok, spec} <- CapabilityMeasurements.fetch(family),
         {:ok, selection} <- selection(request),
         {:ok, units} <- Fount.Selection.select(model, selection),
         {:ok, source} <- source_inputs(units, opts),
         true <- source.inputs != [],
         {:ok, subject} <- subject(family, request, source),
         {:ok, records} <- story_world_records(request),
         {:ok, world} <-
           StoryWorld.compile(model, [],
             records: records,
             evidence_registry: source.evidence
           ),
         {:ok, reader} <- reader(model, family, request),
         {:ok, inputs} <- build_inputs(family, subject, request, source.groups),
         true <- inputs != [] do
      {:ok,
       %{
         spec: spec,
         selection: selection,
         inputs: inputs,
         subject: subject,
         intent: Map.get(request, "intent", %{}),
         records: records,
         world: world,
         reader: reader,
         coverage: Map.put(source.coverage, "measurement_input_count", length(inputs))
       }}
    else
      false -> {:error, :empty_capability_selection}
      error -> error
    end
  end

  defp prepare(_, _, _, _), do: {:error, :invalid_capability_request}

  defp source_inputs(units, opts) do
    scene_cap = Keyword.get(opts, :max_capability_scenes, @default_scene_cap)

    fragment_cap =
      Keyword.get(opts, :max_capability_fragments_per_scene, @default_fragments_per_scene)

    if valid_positive_cap?(scene_cap) and valid_positive_cap?(fragment_cap) do
      grouped =
        units
        |> Enum.reject(&is_nil(&1["scene_id"]))
        |> Enum.group_by(& &1["scene_id"])
        |> Enum.sort_by(fn {_scene_id, scene_units} ->
          Enum.min(Enum.map(scene_units, & &1["ordinal"]))
        end)

      selected_groups = Enum.take(grouped, scene_cap)

      groups =
        Enum.map(selected_groups, fn {scene_id, scene_units} ->
          kept = Enum.take(scene_units, fragment_cap)
          {scene_id, Fount.Selection.evidence(kept), length(scene_units) > length(kept), kept}
        end)

      evidence = Enum.flat_map(groups, fn {_scene, items, _truncated, _units} -> items end)

      {:ok,
       %{
         inputs: evidence,
         evidence: evidence,
         groups: groups,
         coverage: %{
           "selected_scene_count" => length(groups),
           "source_scene_count" => length(grouped),
           "scene_cap_reached" => length(grouped) > length(groups),
           "fragment_cap_reached_scene_ids" => for({scene, _items, true, _units} <- groups, do: scene),
           "evidence_fragment_count" => length(evidence)
         }
       }}
    else
      {:error, :invalid_capability_source_cap}
    end
  end

  defp build_inputs("dialogue_interaction" = family, subject, request, groups) do
    groups
    |> Enum.reduce_while({:ok, []}, fn {scene_id, _evidence, truncated?, units}, {:ok, acc} ->
      with {:ok, context} <- dialogue_context(request, scene_id),
           pairs <- dialogue_pairs(units),
           true <- pairs != [] do
        inputs =
          Enum.map(pairs, fn pair ->
            evidence = pair["evidence"]

            %{
              "id" => "capability:#{family}:scene:#{scene_id}:pair:#{pair["ordinal"]}",
              "scene_id" => scene_id,
              "pair_ordinal" => pair["ordinal"],
              "turn_pair" => Map.take(pair, ~w(previous current)),
              "context_slot_names" => context.slots |> Map.keys() |> Enum.sort(),
              "context" => context,
              "state" => %{
                "family" => family,
                "subject" => Model.plain(subject),
                "writer_intent" => Model.plain(Map.get(request, "intent", %{})),
                "turn_pair" => Map.take(pair, ~w(previous current)),
                "source" => Enum.map(evidence, &Map.take(&1, ~w(evidence_id excerpt target role))),
                "source_truncated_for_host_limit" => truncated?
              },
              "target" => %{"kind" => "scene", "id" => scene_id},
              "evidence" => evidence
            }
          end)

        {:cont, {:ok, acc ++ inputs}}
      else
        false -> {:cont, {:ok, acc}}
        error -> {:halt, error}
      end
    end)
  end

  defp build_inputs(family, subject, request, groups) do
    intent = Map.get(request, "intent", %{})

    {:ok,
     Enum.map(groups, fn {scene_id, evidence, truncated?, _units} ->
       %{
         "id" => "capability:#{family}:scene:#{scene_id}",
         "scene_id" => scene_id,
         "state" => %{
           "family" => family,
           "subject" => Model.plain(subject),
           "writer_intent" => Model.plain(intent),
           "source" => Enum.map(evidence, &Map.take(&1, ~w(evidence_id excerpt target role))),
           "source_truncated_for_host_limit" => truncated?
         },
         "target" => %{"kind" => "scene", "id" => scene_id},
         "evidence" => evidence
       }
     end)}
  end

  defp dialogue_pairs(units) do
    turns = dialogue_turns(units)

    cond do
      length(turns) >= 2 ->
        turns
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.with_index(1)
        |> Enum.map(fn {[previous, current], ordinal} ->
          %{
            "ordinal" => ordinal,
            "previous" => Map.drop(previous, ["evidence"]),
            "current" => Map.drop(current, ["evidence"]),
            "evidence" => Enum.uniq_by(previous["evidence"] ++ current["evidence"], & &1["evidence_id"])
          }
        end)

      length(turns) == 1 ->
        [turn] = turns

        [
          %{
            "ordinal" => 1,
            "previous" => nil,
            "current" => Map.drop(turn, ["evidence"]),
            "evidence" => turn["evidence"]
          }
        ]

      true ->
        []
    end
  end

  defp dialogue_turns(units) do
    {turns, cue} =
      Enum.reduce(units, {[], nil}, fn unit, {turns, cue} ->
        case unit["type"] do
          "character" ->
            cue = %{
              "speaker" => String.trim(unit["text"] || unit["excerpt"] || ""),
              "evidence" => Fount.Selection.evidence([unit])
            }

            {turns, cue}

          "dialogue" ->
            dialogue_evidence = Fount.Selection.evidence([unit])
            cue_evidence = if is_map(cue), do: cue["evidence"] || [], else: []

            turn = %{
              "speaker" => if(is_map(cue), do: cue["speaker"], else: "UNKNOWN"),
              "text" => unit["text"] || unit["excerpt"],
              "element_id" => get_in(unit, ["target", "id"]),
              "evidence" => Enum.uniq_by(cue_evidence ++ dialogue_evidence, & &1["evidence_id"])
            }

            {turns ++ [turn], cue}

          _ ->
            {turns, cue}
        end
      end)

    _ = cue
    turns
  end

  defp dialogue_context(request, scene_id) do
    global = Map.get(request, "dialogue_context", %{})
    by_scene = Map.get(request, "dialogue_context_by_scene", %{})

    slots =
      cond do
        is_map(by_scene) and is_map(by_scene[scene_id]) -> Map.merge(global_if_map(global), by_scene[scene_id])
        is_map(global) -> global
        true -> :invalid
      end

    case slots do
      :invalid -> {:error, :invalid_dialogue_context}
      slots -> ContextBuilder.validate("dialogue.exchange", slots)
    end
  end

  defp global_if_map(value) when is_map(value), do: value
  defp global_if_map(_), do: %{}

  defp annotate_entries(entries, inputs) do
    metadata =
      Map.new(inputs, fn input ->
        {input["id"],
         %{
           "scene_id" => input["scene_id"],
           "pair_ordinal" => input["pair_ordinal"],
           "turn_pair" => input["turn_pair"],
           "context_slots" => input["context_slot_names"] || []
         }}
      end)

    Enum.map(entries, fn entry -> Map.merge(entry, metadata[entry["input_id"]] || %{}) end)
  end

  defp selection(%{"selection" => selection}) when is_map(selection), do: {:ok, selection}
  defp selection(_), do: {:error, :capability_selection_required}

  defp subject("scene_engine", %{"subject" => subject}, _source), do: {:ok, subject}

  defp subject("scene_engine", request, source) do
    scene_id = request["scene_id"] || source.groups |> List.first() |> elem(0)
    {:ok, %{"scene_id" => scene_id}}
  end

  defp subject("agency_causality", %{"subject" => subject}, _source),
    do: validate_character(subject)

  defp subject("character_trajectory", %{"subject" => subject}, _source),
    do: validate_character(subject)

  defp subject("relationship_dynamics", %{"subject" => subject}, _source),
    do: validate_pair(subject)

  defp subject(family, %{"subject" => subject}, _source)
       when family in ~w(audience_reader_experience sequence_movement dialogue_interaction setup_payoff_motifs),
       do: {:ok, subject}

  defp subject("sequence_movement", _request, source),
    do: {:ok, %{"scene_ids" => Enum.map(source.groups, &elem(&1, 0))}}

  defp subject(family, _request, _source)
       when family in ~w(audience_reader_experience dialogue_interaction setup_payoff_motifs),
       do: {:ok, %{"scope" => "selection"}}

  defp subject(_, _, _), do: {:error, :capability_subject_required}

  defp validate_character(%{"character" => character} = subject)
       when is_binary(character) and character != "", do: {:ok, subject}

  defp validate_character(%{"character_id" => character} = subject)
       when is_binary(character) and character != "", do: {:ok, subject}

  defp validate_character(character) when is_binary(character) and character != "",
    do: {:ok, character}

  defp validate_character(_), do: {:error, :character_subject_required}

  defp validate_pair(%{"characters" => [left, right | _] = characters} = subject)
       when not is_nil(left) and not is_nil(right),
       do: {:ok, Map.put(subject, "characters", characters)}

  defp validate_pair(%{"pair" => [left, right | _] = characters} = subject)
       when not is_nil(left) and not is_nil(right),
       do: {:ok, Map.put(subject, "pair", characters)}

  defp validate_pair([left, right | _] = characters) when not is_nil(left) and not is_nil(right),
    do: {:ok, characters}

  defp validate_pair(_), do: {:error, :relationship_pair_required}

  defp reader(model, "audience_reader_experience", request) do
    case Map.get(request, "reader_events") do
      nil -> {:ok, nil}
      events when is_list(events) -> Reader.reduce(model, events)
      _ -> {:error, :invalid_reader_events}
    end
  end

  defp reader(_model, _family, _request), do: {:ok, nil}

  defp story_world_records(request) do
    case Map.get(request, "story_world_records", []) do
      records when is_list(records) ->
        if Enum.all?(records, &is_map/1),
          do: {:ok, records},
          else: {:error, :invalid_story_world_records}

      _ ->
        {:error, :invalid_story_world_records}
    end
  end

  defp run_families(model, families, request, clients, opts) do
    Enum.reduce_while(families, {:ok, []}, fn family, {:ok, acc} ->
      case run(model, family, request, clients, opts) do
        {:ok, result} -> {:cont, {:ok, acc ++ [result]}}
        error -> {:halt, error}
      end
    end)
  end

  defp packet(model, definition, request, results) do
    maps = Enum.map(results, &Result.to_map/1)
    diagnoses = Enum.flat_map(maps, & &1["diagnoses"])
    evidence = maps |> Enum.flat_map(& &1["evidence"]) |> uniq_evidence()
    status = if Enum.all?(results, &(&1.status == "complete")), do: "complete", else: "partial"

    WriterPacket.new(
      definition["id"],
      model.revision.id,
      normalize_concern(request),
      %{
        status: status,
        scope: %{
          "selection" => request["selection"],
          "subject" => Model.plain(request["subject"])
        },
        intent: Map.get(request, "intent", %{}),
        finding: concise_finding(definition, diagnoses),
        coverage: %{
          "families" => Enum.map(results, &%{"family" => &1.family, "status" => &1.status}),
          "complete" => status == "complete"
        },
        evidence: evidence,
        derived_state: Map.new(maps, &{&1["family"], &1["derived_state"]}),
        trajectory:
          Enum.flat_map(
            maps,
            &[%{"family" => &1["family"], "trajectories" => &1["trajectories"]}]
          ),
        diagnoses: diagnoses,
        uncertainty: Enum.flat_map(maps, & &1["uncertainty"]),
        protected_strengths: List.wrap(request["protected_strengths"] || []),
        next_investigations: maps |> Enum.flat_map(& &1["next_investigations"]) |> Enum.uniq(),
        strategies: List.wrap(request["strategies"] || []),
        resource_usage: combined_usage(results),
        errors: maps |> Enum.flat_map(&(get_in(&1, ["metadata", "measurement_errors"]) || [])),
        provenance: %{
          "phase" => packet_phase(results),
          "capability_families" => Enum.map(results, & &1.family),
          "measurement_spec_sha256" =>
            Map.new(results, &{&1.family, &1.metadata["measurement_spec_sha256"]}),
          "playbook_definition" => definition
        },
        limitations:
          maps
          |> Enum.flat_map(& &1["limitations"])
          |> Kernel.++([
            "Installed capability families through Phase 7 provide source-grounded analysis and writer-facing diagnosis; they do not generate replacement screenplay pages.",
            "Workshop candidate generation/acceptance integration remains a later phase; no later-phase functionality is claimed here.",
            "No human reader/usefulness claim is made unless a separate rights-cleared study records one."
          ])
          |> Enum.uniq(),
        candidate: nil
      }
    )
  end

  defp normalize_concern(%{"concern" => %{} = concern}), do: concern

  defp normalize_concern(%{"concern" => concern}) when is_binary(concern),
    do: %{"summary" => concern}

  defp normalize_concern(_),
    do: %{
      "summary" =>
        "Inspect the selected screenplay material using the requested installed capability families."
    }

  defp concise_finding(definition, []),
    do:
      "#{definition["label"]} found no diagnosis that crossed its current evidence rules; inspect uncertainty and missing StoryWorld records before treating this as a clean bill of health."

  defp concise_finding(definition, diagnoses) do
    labels = diagnoses |> Enum.take(3) |> Enum.map_join(", ", & &1["id"])
    remainder = max(length(diagnoses) - 3, 0)
    suffix = if remainder > 0, do: " (+#{remainder} more)", else: ""

    "#{definition["label"]} surfaced source-grounded diagnosis candidates: #{labels}#{suffix}. They remain hypotheses until the writer inspects the cited evidence and alternatives."
  end

  defp combined_usage(results) do
    usages =
      Enum.map(results, & &1.metadata["measurement_resource_usage"]) |> Enum.reject(&is_nil/1)

    %{"capability_runs" => usages, "family_count" => length(results)}
  end

  defp packet_phase(results) do
    if Enum.any?(results, &(&1.family in ~w(audience_reader_experience sequence_movement dialogue_interaction setup_payoff_motifs))),
      do: 7,
      else: 6
  end

  defp measurement_opts(opts, model, lens_id, cap) do
    opts
    |> Keyword.put(:source_model, model)
    |> Keyword.put(:lens_id, lens_id)
    |> Keyword.put(:max_provider_requests, max(cap, 0))
  end

  defp provider(clients) when is_map(clients) do
    case Map.get(clients, :observe, Map.get(clients, "observe")) do
      nil -> {:error, :observe_provider_required}
      provider -> {:ok, provider}
    end
  end

  defp provider(_), do: {:error, :observe_provider_required}

  defp provider_cap(opts) do
    value = Keyword.get(opts, :max_capability_provider_requests, @default_provider_cap)

    if is_integer(value) and value >= 0 and value <= 10_000,
      do: {:ok, value},
      else: {:error, :invalid_resource_cap}
  end

  defp families_for_playbook(playbook) do
    case @playbook_families[playbook] do
      nil -> {:error, :capability_playbook_not_supported}
      families -> {:ok, families}
    end
  end

  defp shared_budget(opts) do
    if Resources.from_options(opts),
      do: opts,
      else: Keyword.put(opts, :analysis_budget, Resources.new(opts))
  end

  defp combined_status(result_status, report_status, coverage) do
    complete_coverage =
      not coverage["scene_cap_reached"] and coverage["fragment_cap_reached_scene_ids"] == []

    if result_status == "complete" and report_status == "complete" and complete_coverage,
      do: "complete",
      else: "partial"
  end

  defp valid_positive_cap?(value), do: is_integer(value) and value > 0 and value <= 10_000

  defp uniq_evidence(evidence) do
    evidence
    |> Enum.filter(&is_map/1)
    |> Enum.uniq_by(&(&1["id"] || &1["evidence_id"] || inspect(&1)))
    |> Enum.sort_by(&(&1["id"] || &1["evidence_id"] || inspect(&1)))
  end
end
