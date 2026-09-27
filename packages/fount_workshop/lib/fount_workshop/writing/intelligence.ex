defmodule FountWorkshop.Writing.Intelligence do
  @moduledoc """
  Phase-9 bridge between writer-controlled Workshop workflows and source-grounded Intelligence.

  Analysis never accepts or mutates canon. Provider-backed analysis is additive: workflows still run
  when no Observe provider is configured, and the resulting metadata says that analysis was not run.
  """

  alias Fount.Intelligence.Reporting.WriterPacket
  alias Fount.Screenplay.Model
  alias Fount.Writing.CanonicalJSON
  alias FountWorkshop.Store

  @playbooks %{
    "alternatives" => "scene_doctor",
    "propagate" => "setup_payoff",
    "sequence" => "sequence_momentum",
    "character" => "character_trajectory",
    "notes" => "scene_doctor",
    "pass" => "scene_doctor",
    "recover" => "scene_doctor",
    "investigate" => "scene_doctor"
  }

  @doc "Provider-free Phase-9 analysis preflight. It never dispatches Observe or Inference calls."
  def preflight(model, request, opts \\ []) do
    case playbook(request) do
      nil ->
        {:ok, unavailable("no_prewrite_playbook_for_workflow")}

      playbook ->
        analysis_request = analysis_request(model, request, nil)

        case Fount.Intelligence.preflight_capability_playbook(
               model,
               playbook,
               analysis_request,
               phase_opts(opts)
             ) do
          {:ok, estimate} ->
            {:ok,
             %{
               "status" => "available",
               "playbook" => playbook,
               "request" => analysis_request,
               "estimate" => estimate,
               "limitations" => [
                 "Preflight dispatches no provider request and changes no screenplay content.",
                 "Actual provider usage and cache reuse are recorded only if analysis runs."
               ]
             }}

          {:error, reason} ->
            {:ok, unavailable(reason, playbook)}
        end
    end
  end

  @doc "Adds note triage plus a writer-facing diagnosis packet when an Observe provider is configured."
  def enrich_preparation(model, request, context, services, opts \\ []) do
    {:ok, preflight} = preflight(model, request, opts)

    data =
      context.data
      |> Map.put("intelligence_preflight", preflight)
      |> put_note_triage(request)

    context = %{context | data: data}

    case {playbook(request), observe_provider(services)} do
      {nil, _} ->
        {:ok, put_packet(context, unavailable("no_prewrite_playbook_for_workflow"))}

      {playbook, nil} ->
        {:ok, put_packet(context, unavailable("observe_provider_not_configured", playbook))}

      {playbook, _provider} ->
        analysis_request = analysis_request(model, request, context)

        case Fount.Intelligence.run_capability_playbook(
               model,
               playbook,
               analysis_request,
               Store.clients(services),
               phase_opts(opts)
             ) do
          {:ok, %WriterPacket{} = packet} ->
            packet_map = WriterPacket.to_map(packet)

            {:ok,
             context
             |> Map.update!(:evidence, fn evidence ->
               Enum.uniq_by(evidence ++ packet.evidence, &evidence_id/1)
             end)
             |> put_packet(packet_map)}

          {:error, reason} ->
            # Analysis is advisory in Workshop. The inability to obtain it must be visible but must
            # not destroy an otherwise valid writing workflow.
            {:ok, put_packet(context, unavailable(reason, playbook))}
        end
    end
  end

  @doc "Runs explicit base/candidate Revision Intelligence and returns a plain writer packet."
  def revision_packet(base, candidate, request, strategy, context, services, opts \\ []) do
    if observe_provider(services) do
      before_selection = valid_selection(base, context.selection)
      after_selection = valid_selection(candidate["screenplay"], context.selection)

      analysis_request = %{
        "before_selection" => before_selection,
        "after_selection" => after_selection,
        "concern" => concern(request),
        "intent" => intent(request),
        "intended_effect" => intended_effect(request, strategy),
        "protected_strengths" => protected_strengths(request),
        "constraints" => Model.plain(request["constraints"] || []),
        "strategy" => Model.plain(strategy),
        "strategies" => Model.plain(Keyword.get(opts, :session_strategies, [])),
        "before_story_world_records" => story_world_records(context, "before"),
        "after_story_world_records" => story_world_records(context, "after")
      }

      case Fount.Intelligence.run_revision_playbook(
             base,
             candidate["screenplay"],
             analysis_request,
             Store.clients(services),
             phase_opts(opts)
           ) do
        {:ok, %WriterPacket{} = packet} -> {:ok, WriterPacket.to_map(packet)}
        {:error, reason} -> {:ok, unavailable(reason, "revision_regression")}
      end
    else
      {:ok, unavailable("observe_provider_not_configured", "revision_regression")}
    end
  end

  @doc "Adds diagnosis/playbook lineage to generated strategies without changing their creative fields."
  def link_strategies(strategies, context) when is_list(strategies) do
    packet = context.data["writer_intelligence"] || %{}

    lineage = %{
      "playbook" => packet["playbook"],
      "packet_id" => packet["id"],
      "diagnosis_ids" => diagnosis_ids(packet),
      "protected_strengths" => packet["protected_strengths"] || [],
      "resource_usage" => packet["resource_usage"] || %{},
      "status" => packet["status"]
    }

    Enum.map(strategies, &Map.put(&1, "intelligence_lineage", lineage))
  end

  @doc "Returns the Phase-9 candidate provenance fields inherited from preparation and strategy."
  def candidate_lineage(request, strategy, context) do
    packet = context.data["writer_intelligence"] || %{}

    %{
      "workflow" => request["workflow"],
      "playbook" => packet["playbook"],
      "concern" => concern(request),
      "pre_analysis_packet_id" => packet["id"],
      "pre_analysis_packet_sha256" => packet_digest(packet),
      "diagnosis_ids" => diagnosis_ids(packet),
      "protected_strengths" => protected_strengths(request),
      "strategy_id" => strategy["id"],
      "strategy_lineage" => strategy["intelligence_lineage"] || %{},
      "consequence_proposals" => List.wrap(strategy["consequences"] || []),
      "resource_preflight" => context.data["intelligence_preflight"] || %{},
      "pre_analysis_packet" => packet,
      "note_triage" => context.data["note_triage"] || []
    }
  end

  @doc false
  def not_run(reason, playbook \\ nil), do: unavailable(reason, playbook)

  @doc "Creates non-blocking review checks from a Revision Intelligence writer packet."
  def revision_checks(%{"status" => status} = packet) when status in ["complete", "partial"] do
    comparison = packet["revision_comparison"] || %{}
    protected = comparison["protected_strengths"] || %{}
    collateral = comparison["collateral_change"] || %{}

    [
      %{
        "constraint_id" => "phase9.protected_strengths",
        "kind" => "revision_intelligence",
        "severity" => "advisory",
        "evaluation" => "semantic",
        "status" => protected_status(protected),
        "measurements" => protected
      },
      %{
        "constraint_id" => "phase9.collateral_change",
        "kind" => "revision_intelligence",
        "severity" => "advisory",
        "evaluation" => "semantic",
        "status" => collateral_status(collateral),
        "measurements" => collateral
      }
    ]
  end

  def revision_checks(_), do: []

  defp analysis_request(model, request, context) do
    %{
      "selection" => selection(model, request, context),
      "subject" => subject(request),
      "concern" => concern(request),
      "intent" => intent(request),
      "protected_strengths" => protected_strengths(request),
      "story_world_records" => story_world_records(context, "current")
    }
  end

  defp selection(model, request, nil),
    do: FountWorkshop.Writing.Context.editable_selection(model, request)

  defp selection(_model, _request, context), do: context.selection

  defp subject(%{"workflow" => "character", "options" => %{"character_id" => id}}),
    do: %{"character_id" => id}

  defp subject(_), do: %{"scope" => "selection"}

  defp concern(%{"workflow" => "notes", "options" => opts} = request) do
    notes =
      (opts["external_notes"] || [])
      |> Enum.map(&note_text/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.take(8)
      |> Enum.join(" | ")

    base =
      "Diagnose the reported writer reaction separately from possible causes and possible treatments."

    if notes == "", do: base <> " " <> request["instruction"], else: base <> " Notes: " <> notes
  end

  defp concern(%{"workflow" => "investigate", "options" => opts} = request),
    do: opts["concern"] || request["instruction"]

  defp concern(%{"workflow" => "propagate", "options" => opts} = request),
    do: "Trace consequences of this story decision: #{opts["change"]}. " <> request["instruction"]

  defp concern(%{"workflow" => "character", "options" => opts} = request),
    do: opts["direction"] || request["instruction"]

  defp concern(%{"workflow" => "pass", "options" => opts} = request),
    do: opts["direction"] || request["instruction"]

  defp concern(request), do: request["instruction"] || "Inspect the selected screenplay material."

  defp intent(request) do
    %{
      "workflow" => request["workflow"],
      "mode" => request["mode"],
      "instruction" => request["instruction"],
      "intended_effect" => get_in(request, ["options", "intended_effect"]),
      "protected_strengths" => protected_strengths(request)
    }
  end

  defp intended_effect(request, strategy) do
    get_in(request, ["options", "intended_effect"]) || strategy["premise_of_change"] ||
      request["instruction"]
  end

  defp protected_strengths(request),
    do: List.wrap(get_in(request, ["options", "protected_strengths"]) || [])

  defp playbook(request), do: Map.get(@playbooks, request["workflow"])

  defp observe_provider(services) when is_map(services), do: services[:observe]
  defp observe_provider(_), do: nil

  defp phase_opts(opts) do
    opts
    |> Keyword.put_new(:max_capability_provider_requests, 120)
    |> Keyword.put_new(:max_capability_scenes, 80)
    |> Keyword.put_new(:max_capability_fragments_per_scene, 24)
  end

  defp put_packet(context, packet),
    do: %{context | data: Map.put(context.data, "writer_intelligence", packet)}

  defp put_note_triage(data, %{"workflow" => "notes", "options" => opts}) do
    items = data["notes"] || external_note_items(opts["external_notes"] || [])
    Map.put(data, "note_triage", Enum.map(items, &triage_note/1))
  end

  defp put_note_triage(data, _), do: data

  defp external_note_items(notes) do
    Enum.with_index(notes, 1)
    |> Enum.map(fn {value, index} ->
      %{"id" => "external-note-#{index}", "source" => "request", "value" => value}
    end)
  end

  defp triage_note(note) do
    value = note["value"] || note[:value] || note

    %{
      "note_id" => note["id"] || note[:id],
      "source" => note["source"] || note[:source] || "screenplay",
      "raw_note" => Model.plain(value),
      "reaction" => explicit(value, ~w(reaction reader_reaction note text)) || note_text(value),
      "suggested_cause" => explicit(value, ~w(suggested_cause cause diagnosis)),
      "suggested_treatment" =>
        explicit(value, ~w(suggested_treatment suggested_solution solution treatment fix)),
      "separation" => "reported_reaction_possible_cause_possible_treatment"
    }
  end

  defp explicit(value, keys) when is_map(value) do
    Enum.find_value(keys, fn key ->
      direct = Map.get(value, key)

      atom_value =
        try do
          Map.get(value, String.to_existing_atom(key))
        rescue
          ArgumentError -> nil
        end

      case direct || atom_value do
        text when is_binary(text) and text != "" -> text
        _ -> nil
      end
    end)
  end

  defp explicit(_, _), do: nil

  defp note_text(value) when is_binary(value), do: String.slice(value, 0, 2_000)

  defp note_text(value) when is_map(value) do
    explicit(value, ~w(note text reaction reader_reaction)) ||
      value |> Model.plain() |> Jason.encode!() |> String.slice(0, 2_000)
  end

  defp note_text(value), do: value |> inspect(limit: 20, printable_limit: 2_000)

  defp valid_selection(model, selection) do
    case Fount.Selection.select(model, selection) do
      {:ok, [_ | _]} -> selection
      _ -> %{"whole_screenplay" => true}
    end
  end

  defp story_world_records(nil, _), do: []

  defp story_world_records(context, side) do
    get_in(context.data, ["story_world_records", side]) || context.data["story_world_records"] || []
  end

  defp diagnosis_ids(packet) when is_map(packet) do
    packet
    |> Map.get("diagnoses", [])
    |> Enum.map(&(&1["id"] || &1[:id]))
    |> Enum.reject(&is_nil/1)
  end

  defp diagnosis_ids(_), do: []

  defp packet_digest(%{"id" => _} = packet), do: CanonicalJSON.hash(packet)
  defp packet_digest(_), do: nil

  defp evidence_id(value), do: value["evidence_id"] || value["id"] || inspect(value)

  defp unavailable(reason, playbook \\ nil) do
    %{
      "status" => "not_run",
      "playbook" => playbook,
      "reason" => safe_reason(reason),
      "diagnoses" => [],
      "protected_strengths" => [],
      "resource_usage" => %{},
      "limitations" => [
        "No writer-facing analysis claim is made for this workflow run.",
        "Screenplay generation and explicit writer review remain available independently."
      ]
    }
  end

  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason(reason) when is_binary(reason), do: reason
  defp safe_reason(_), do: "analysis_unavailable"

  defp protected_status(%{"declared" => []}), do: "not_applicable"
  defp protected_status(%{"status" => "evidence_of_preservation"}), do: "pass"
  defp protected_status(%{}), do: "unresolved"
  defp protected_status(_), do: "not_run"

  defp collateral_status(%{"risk_support" => risks}) when is_map(risks) do
    if Enum.any?(risks, fn {_key, count} -> is_number(count) and count > 0 end),
      do: "review",
      else: "pass"
  end

  defp collateral_status(_), do: "unresolved"
end
