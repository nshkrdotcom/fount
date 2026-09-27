defmodule Fount.Intelligence.Playbooks.CapabilityRunner do
  @moduledoc "Capability shell through Phase 8: exact screenplay selection -> validated Observe measurements -> pure reasoning -> optional writer packet and explicit two-revision comparison."

  alias Fount.Intelligence.Acquisition.{CapabilityMeasurements, ContextBuilder, Measurements}
  alias Fount.Intelligence.Capabilities
  alias Fount.Intelligence.Capabilities.Result
  alias Fount.Intelligence.Packs
  alias Fount.Intelligence.Persistence
  alias Fount.Intelligence.Playbooks.{StrategyContrast, WriterRegistry}
  alias Fount.Intelligence.Reader
  alias Fount.Intelligence.Reporting.WriterPacket
  alias Fount.Intelligence.Runner.Resources
  alias Fount.Intelligence.StoryWorld
  alias Fount.Screenplay.Model
  alias Fount.Writing.CanonicalJSON

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
    "setup_payoff" => ~w(setup_payoff_motifs),
    "submission_read" => ~w(theme_meaning)
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
    with {:ok, families} <- families_for_playbook(playbook, request) do
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
         {:ok, families} <- families_for_playbook(playbook, request),
         {:ok, run, run_opts} <- begin_persistence(model, playbook, definition, request, opts) do
      case run_families(model, families, request, clients, shared_budget(run_opts)) do
        {:ok, results} ->
          finish_results(run, packet(model, definition, request, results))

        {:error, reason} = error ->
          Persistence.fail(run, reason)
          error
      end
    end
  end

  @doc "Provider-free preflight for an explicit base/candidate Revision Intelligence comparison."
  def preflight_revision(before_model, after_model, request, opts \\ [])

  def preflight_revision(before_model, after_model, request, opts) when is_map(request) do
    before_request = revision_request(request, :before)
    after_request = revision_request(request, :after)

    with {:ok, before_prepared} <-
           prepare(before_model, "revision_intelligence", before_request, opts),
         {:ok, after_prepared} <-
           prepare(after_model, "revision_intelligence", after_request, opts),
         {:ok, cap} <- provider_cap(opts),
         {:ok, before_estimate} <-
           Measurements.preflight(
             before_prepared.inputs,
             before_prepared.spec["questions"],
             measurement_opts(
               opts,
               before_model,
               before_prepared.spec["lens_id"],
               min(cap, length(before_prepared.inputs))
             )
           ),
         {:ok, after_estimate} <-
           Measurements.preflight(
             after_prepared.inputs,
             after_prepared.spec["questions"],
             measurement_opts(
               opts,
               after_model,
               after_prepared.spec["lens_id"],
               min(cap, length(after_prepared.inputs))
             )
           ) do
      {:ok,
       %{
         "family" => "revision_intelligence",
         "before_revision_id" => before_model.revision.id,
         "after_revision_id" => after_model.revision.id,
         "before" => %{"coverage" => before_prepared.coverage, "estimate" => before_estimate},
         "after" => %{"coverage" => after_prepared.coverage, "estimate" => after_estimate},
         "strategy_contrast_requested" => strategy_request?(request),
         "limitations" => [
           "Preflight dispatches no provider requests and does not claim that the intended effect or protected strengths are satisfied.",
           "Base and candidate StoryWorld/Reader inputs are revision-specific; missing derived records remain unknown."
         ]
       }}
    end
  rescue
    _ in [ArgumentError, KeyError, FunctionClauseError, MatchError, BadMapError] ->
      {:error, :invalid_revision_comparison_request}
  end

  def preflight_revision(_, _, _, _), do: {:error, :invalid_revision_comparison_request}

  @doc "Runs explicit base/candidate Revision Intelligence without generating, ranking, accepting or rejecting screenplay pages."
  def run_revision(before_model, after_model, request, clients \\ %{}, opts \\ [])

  def run_revision(before_model, after_model, request, clients, opts) when is_map(request) do
    before_request = revision_request(request, :before)
    after_request = revision_request(request, :after)

    with {:ok, provider} <- provider(clients),
         {:ok, before_prepared} <-
           prepare(before_model, "revision_intelligence", before_request, opts),
         {:ok, after_prepared} <-
           prepare(after_model, "revision_intelligence", after_request, opts),
         {:ok, cap} <- provider_cap(opts),
         {:ok, before_report, before_entries} <-
           measure_prepared(provider, before_model, before_prepared, cap, opts),
         {:ok, after_report, after_entries} <-
           measure_prepared(provider, after_model, after_prepared, cap, opts),
         {:ok, strategy} <- strategy_contrast(after_model, request, provider, opts),
         {:ok, result} <-
           Capabilities.compare_revision(
             before_prepared.world,
             after_prepared.world,
             after_prepared.subject,
             before_entries,
             after_entries,
             revision_compare_opts(
               before_model,
               after_model,
               request,
               before_prepared,
               after_prepared,
               strategy
             )
           ) do
      result =
        %{
          result
          | status:
              if(
                combined_status(result.status, before_report["status"], before_prepared.coverage) ==
                  "complete" and
                  combined_status(result.status, after_report["status"], after_prepared.coverage) ==
                    "complete",
                do: "complete",
                else: "partial"
              ),
            metadata:
              Map.merge(result.metadata, %{
                "before_measurement_spec_sha256" => before_report["measurement_spec_sha256"],
                "after_measurement_spec_sha256" => after_report["measurement_spec_sha256"],
                "before_measurement_resource_usage" => before_report["resource_usage"],
                "after_measurement_resource_usage" => after_report["resource_usage"],
                "before_measurement_errors" => before_report["errors"],
                "after_measurement_errors" => after_report["errors"],
                "before_selection_coverage" => before_prepared.coverage,
                "after_selection_coverage" => after_prepared.coverage
              })
        }

      {:ok, result}
    end
  rescue
    _ in [ArgumentError, KeyError, FunctionClauseError, MatchError, BadMapError] ->
      {:error, :invalid_revision_comparison_request}
  end

  def run_revision(_, _, _, _, _), do: {:error, :invalid_revision_comparison_request}

  @doc "Returns the existing revision_regression writer packet around an explicit two-revision capability comparison."
  def run_revision_playbook(
        before_model,
        after_model,
        playbook,
        request,
        clients \\ %{},
        opts \\ []
      )

  def run_revision_playbook(
        before_model,
        after_model,
        "revision_regression",
        request,
        clients,
        opts
      ) do
    with {:ok, definition} <- WriterRegistry.fetch("revision_regression"),
         {:ok, run, run_opts} <-
           begin_persistence(after_model, "revision_regression", definition, request, opts) do
      case run_revision(before_model, after_model, request, clients, shared_budget(run_opts)) do
        {:ok, result} ->
          finish_results(run, packet(after_model, definition, request, [result]))

        {:error, reason} = error ->
          Persistence.fail(run, reason)
          error
      end
    end
  end

  def run_revision_playbook(_, _, _, _, _, _), do: {:error, :capability_playbook_not_supported}

  defp finish_results(run, {:ok, packet}) do
    case Persistence.finish_packet(run, packet) do
      {:ok, _} = result ->
        result

      {:error, reason} = error ->
        Persistence.fail(run, reason)
        error
    end
  end

  defp finish_results(run, {:error, reason} = error) do
    Persistence.fail(run, reason)
    error
  end

  defp begin_persistence(model, playbook, definition, request, opts) do
    case Keyword.get(opts, :analysis_store) do
      %Persistence{} = store ->
        attrs = %{
          "session_id" => Keyword.get(opts, :analysis_session_id),
          "candidate_id" => Keyword.get(opts, :analysis_candidate_id),
          "playbook_sha256" => CanonicalJSON.hash(definition),
          "concern" => normalize_concern(request),
          "intent" => Map.get(request, "intent", %{}),
          "scope" => %{
            "selection" => request["selection"],
            "subject" => Model.plain(request["subject"])
          },
          "preflight" => Keyword.get(opts, :analysis_preflight, %{}),
          "metadata" => %{
            "changes_canon" => false,
            "analysis_kind" => "writer_playbook"
          }
        }

        with {:ok, run} <- Persistence.begin(store, model, playbook, attrs) do
          {:ok, run,
           Persistence.measurement_options(run, opts) |> Keyword.put(:analysis_run, run)}
        end

      _ ->
        {:ok, nil, opts}
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
           "fragment_cap_reached_scene_ids" =>
             for({scene, _items, true, _units} <- groups, do: scene),
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
          Enum.map(
            pairs,
            &dialogue_input(&1, family, scene_id, subject, request, context, truncated?)
          )

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

  defp dialogue_input(pair, family, scene_id, subject, request, context, truncated?) do
    evidence = pair["evidence"]
    turn_pair = Map.take(pair, ~w(previous current))

    %{
      "id" => "capability:#{family}:scene:#{scene_id}:pair:#{pair["ordinal"]}",
      "scene_id" => scene_id,
      "pair_ordinal" => pair["ordinal"],
      "turn_pair" => turn_pair,
      "context_slot_names" => context.slots |> Map.keys() |> Enum.sort(),
      "context" => context,
      "state" => %{
        "family" => family,
        "subject" => Model.plain(subject),
        "writer_intent" => Model.plain(Map.get(request, "intent", %{})),
        "turn_pair" => turn_pair,
        "source" => Enum.map(evidence, &Map.take(&1, ~w(evidence_id excerpt target role))),
        "source_truncated_for_host_limit" => truncated?
      },
      "target" => %{"kind" => "scene", "id" => scene_id},
      "evidence" => evidence
    }
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
            "evidence" =>
              Enum.uniq_by(previous["evidence"] ++ current["evidence"], & &1["evidence_id"])
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
    {turns, _cue} =
      Enum.reduce(units, {[], nil}, fn unit, {turns, cue} ->
        case unit["type"] do
          "character" ->
            {turns, dialogue_cue(unit)}

          "dialogue" when is_map(cue) ->
            {[dialogue_turn(unit, cue) | turns], cue}

          "action" ->
            {turns, nil}

          _ ->
            {turns, cue}
        end
      end)

    Enum.reverse(turns)
  end

  defp dialogue_cue(unit) do
    speaker = String.trim(unit["text"] || unit["excerpt"] || "")

    if speaker == "",
      do: nil,
      else: %{"speaker" => speaker, "evidence" => Fount.Selection.evidence([unit])}
  end

  defp dialogue_turn(unit, cue) do
    evidence = Fount.Selection.evidence([unit])

    %{
      "speaker" => cue["speaker"],
      "text" => unit["text"] || unit["excerpt"],
      "element_id" => get_in(unit, ["target", "id"]),
      "evidence" => Enum.uniq_by(cue["evidence"] ++ evidence, & &1["evidence_id"])
    }
  end

  defp dialogue_context(request, scene_id) do
    global = Map.get(request, "dialogue_context", %{})
    by_scene = Map.get(request, "dialogue_context_by_scene", %{})

    slots =
      cond do
        is_map(by_scene) and is_map(by_scene[scene_id]) ->
          Map.merge(global_if_map(global), by_scene[scene_id])

        is_map(global) ->
          global

        true ->
          :invalid
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

  defp subject("emotional_value_movement", %{"subject" => subject}, _source),
    do: validate_character(subject)

  defp subject("genre_lens_packs", request, _source) do
    custom_lenses = Map.get(request, "custom_lenses", %{})

    with true <- is_map(custom_lenses),
         pack when not is_nil(pack) <- Map.get(request, "genre_pack"),
         {:ok, resolved} <- Packs.resolve(pack, custom_lenses: custom_lenses) do
      {:ok, %{"genre_pack" => resolved}}
    else
      false -> {:error, :invalid_custom_lens_catalog}
      nil -> {:error, :genre_pack_required}
      error -> error
    end
  end

  defp subject("revision_intelligence", request, _source) do
    {:ok,
     %{
       "intended_effect" => request["intended_effect"],
       "protected_strengths" => List.wrap(request["protected_strengths"] || []),
       "constraints" => List.wrap(request["constraints"] || []),
       "strategy" => request["strategy"]
     }}
  end

  defp subject(family, %{"subject" => subject}, _source)
       when family in ~w(audience_reader_experience sequence_movement dialogue_interaction setup_payoff_motifs theme_meaning),
       do: {:ok, subject}

  defp subject("sequence_movement", _request, source),
    do: {:ok, %{"scene_ids" => Enum.map(source.groups, &elem(&1, 0))}}

  defp subject(family, _request, _source)
       when family in ~w(audience_reader_experience dialogue_interaction setup_payoff_motifs theme_meaning),
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

  defp reader(model, family, request)
       when family in ~w(audience_reader_experience revision_intelligence) do
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
        revision_comparison: revision_comparison(maps),
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
            "Installed capability families through Phase 8 provide source-grounded analysis and writer-facing diagnosis/comparison; they do not generate replacement screenplay pages.",
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

  defp revision_comparison(maps) do
    case Enum.find(maps, &(&1["family"] == "revision_intelligence")) do
      nil -> nil
      result -> result["derived_state"]
    end
  end

  defp combined_usage(results) do
    usages =
      Enum.map(results, & &1.metadata["measurement_resource_usage"]) |> Enum.reject(&is_nil/1)

    %{"capability_runs" => usages, "family_count" => length(results)}
  end

  defp packet_phase(results) do
    cond do
      Enum.any?(
        results,
        &(&1.family in ~w(emotional_value_movement theme_meaning genre_lens_packs revision_intelligence))
      ) ->
        8

      Enum.any?(
        results,
        &(&1.family in ~w(audience_reader_experience sequence_movement dialogue_interaction setup_payoff_motifs))
      ) ->
        7

      true ->
        6
    end
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

  defp families_for_playbook("revision_regression", _request),
    do: {:error, :use_explicit_revision_playbook}

  defp families_for_playbook(playbook, request) do
    case @playbook_families[playbook] do
      nil ->
        {:error, :capability_playbook_not_supported}

      families ->
        {:ok, Enum.uniq(families ++ extra_families(playbook, request))}
    end
  end

  defp extra_families("character_trajectory", %{"include_emotional_value_movement" => true}),
    do: ["emotional_value_movement"]

  defp extra_families("submission_read", %{"genre_pack" => pack}) when not is_nil(pack),
    do: ["genre_lens_packs"]

  defp extra_families(_, _), do: []

  defp measure_prepared(provider, model, prepared, cap, opts) do
    with {:ok, report} <-
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
           ) do
      {:ok, report, annotate_entries(report["entries"], prepared.inputs)}
    end
  end

  defp revision_request(request, side) do
    prefix = if side == :before, do: "before", else: "after"

    selection =
      request["#{prefix}_selection"] || request["selection"] || %{"whole_screenplay" => true}

    records = request["#{prefix}_story_world_records"] || request["story_world_records"] || []
    reader_events = request["#{prefix}_reader_events"]

    request
    |> Map.put("selection", selection)
    |> Map.put("story_world_records", records)
    |> Map.put("reader_events", reader_events)
    |> Map.put("intent", revision_intent(request))
  end

  defp revision_intent(request) do
    base = if is_map(request["intent"]), do: request["intent"], else: %{}

    Map.merge(base, %{
      "intended_effect" => request["intended_effect"],
      "protected_strengths" => List.wrap(request["protected_strengths"] || []),
      "constraints" => List.wrap(request["constraints"] || []),
      "strategy" => request["strategy"]
    })
  end

  defp revision_compare_opts(
         before_model,
         after_model,
         request,
         before_prepared,
         after_prepared,
         strategy
       ) do
    [
      intent: revision_intent(request),
      concern: request["concern"],
      strategy: request["strategy"],
      intended_effect: request["intended_effect"],
      protected_strengths: List.wrap(request["protected_strengths"] || []),
      constraints: List.wrap(request["constraints"] || []),
      before_reader: before_prepared.reader,
      after_reader: after_prepared.reader,
      structural_diff: Fount.Screenplay.diff(before_model, after_model),
      source_diff:
        String.myers_difference(
          Fount.Screenplay.to_fountain(before_model),
          Fount.Screenplay.to_fountain(after_model)
        ),
      strategy_contrast: strategy
    ]
  end

  defp strategy_contrast(model, request, provider, opts) do
    if strategy_request?(request) do
      params = %{
        "brief" =>
          request["strategy_brief"] || request["concern"] || "Revision strategy contrast",
        "strategies" => request["strategies"]
      }

      case StrategyContrast.run(model, params, %{observe: provider}, opts) do
        {:ok, report} ->
          {:ok, report.data}

        {:error, reason} ->
          {:ok,
           %{
             "status" => "unavailable",
             "reason" =>
               if(is_atom(reason), do: to_string(reason), else: "provider_or_contract_error")
           }}
      end
    else
      {:ok, %{"status" => "not_requested"}}
    end
  end

  defp strategy_request?(request),
    do: is_list(request["strategies"]) and length(request["strategies"]) in 2..5

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
