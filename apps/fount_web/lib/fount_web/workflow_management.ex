defmodule FountWeb.WorkflowManagement do
  @moduledoc """
  Host-owned Phase 07 policy, workflow, selection, comparison and notification helpers.

  This module never manufactures ActorContext identity from browser fields. It validates
  policy through FountRun.Policy, request scope through Fount.Selection and writer requests
  through FountWorkshop.Request before any durable Run mutation is attempted.
  """

  alias Fount.Writing.{CanonicalJSON, Principal}
  alias FountRun.{ActorContext, Policy}

  @gate_keys ~w(investigation_scope strategy_choice candidate_generation iteration)
  @gate_modes ~w(automatic human)
  @limit_keys ~w(max_iterations max_malformed_repairs_per_call max_transient_retries max_inference_calls max_measurement_states)
  @terminal ~w(completed_candidate completed_accepted stopped failed)
  @max_instruction_bytes 4_096
  @max_scope_targets 64
  @max_multi_launch 8
  @max_run_list 50

  @action_catalog [
    %{
      "id" => "develop",
      "label" => "Develop",
      "enabled" => true,
      "mode" => "revise",
      "request" => "FountWorkshop.Request workflow=develop; placement=start",
      "handler" => "FountRun.PipelineRequest → PipelineHandler → WorkshopHandler",
      "preconditions" => "authorized exact base revision and validated screenplay selection"
    },
    %{
      "id" => "propagate",
      "label" => "Propagate change",
      "enabled" => true,
      "mode" => "revise",
      "request" => "FountWorkshop.Request workflow=propagate; change + repair_scope",
      "handler" => "FountRun.PipelineRequest → PipelineHandler → WorkshopHandler",
      "preconditions" => "nonempty instruction, exact base revision and validated screenplay selection"
    },
    %{
      "id" => "pass",
      "label" => "Focused pass",
      "enabled" => true,
      "mode" => "revise",
      "request" => "FountWorkshop.Request workflow=pass; profile=dialogue_subtext",
      "handler" => "FountRun.PipelineRequest → PipelineHandler → WorkshopHandler",
      "preconditions" => "authorized exact base revision and validated screenplay selection"
    },
    %{
      "id" => "alternatives",
      "label" => "Alternatives",
      "enabled" => false,
      "mode" => "explore",
      "request" => "FountWorkshop.Workflows.alternatives/4 exists",
      "handler" => "not enabled by the Phase 07 host catalog",
      "preconditions" => "no retained durable-host launch proof for this exact action schema"
    },
    %{
      "id" => "sequence",
      "label" => "Sequence",
      "enabled" => false,
      "mode" => "revise",
      "request" => "FountWorkshop.Workflows.sequence/4 requires target_scene_count",
      "handler" => "not enabled by the Phase 07 host catalog",
      "preconditions" => "requires an explicit sequence contract not exposed by this surface"
    },
    %{
      "id" => "character",
      "label" => "Character",
      "enabled" => false,
      "mode" => "revise",
      "request" => "FountWorkshop.Workflows.character/4 requires character_id + direction",
      "handler" => "not enabled by the Phase 07 host catalog",
      "preconditions" => "character-specific action surface is not present"
    },
    %{
      "id" => "notes",
      "label" => "Notes",
      "enabled" => false,
      "mode" => "revise",
      "request" => "FountWorkshop.Workflows.notes/4 requires authored note identities",
      "handler" => "not enabled by the Phase 07 host catalog",
      "preconditions" => "Phase 08 owns production note tooling"
    },
    %{
      "id" => "recover",
      "label" => "Recover",
      "enabled" => false,
      "mode" => "revise",
      "request" => "FountWorkshop.Workflows.recover/4 requires source/destination bindings",
      "handler" => "not enabled by the Phase 07 host catalog",
      "preconditions" => "no arbitrary source/destination launch is exposed"
    },
    %{
      "id" => "investigate",
      "label" => "Investigate",
      "enabled" => false,
      "mode" => "diagnose",
      "request" => "FountWorkshop.Workflows.investigate/4 exists",
      "handler" => "durable Run already owns an investigate stage; wrapper is not promoted to a Run action",
      "preconditions" => "diagnosis helper is not a separately proven durable Run launch"
    }
  ]

  def action_catalog, do: @action_catalog
  def enabled_actions, do: Enum.filter(@action_catalog, & &1["enabled"])

  def policy_contract do
    %{
      "gates" => @gate_keys,
      "gate_modes" => @gate_modes,
      "completion" => ~w(candidate accept),
      "route_choices" => ["pause_on_material_tradeoff", "registered_reviewer"],
      "limits" => @limit_keys,
      "money" => %{"currency" => "ISO-4217 three-letter code", "max_microunits" => "nonnegative integer"}
    }
  end

  def policy_from_form(params, %ActorContext{} = context, owner_id) when is_map(params) do
    with :ok <- trusted_owner(context, owner_id),
         {:ok, gates} <- gates_from_form(params),
         {:ok, completion} <- enum(params["completion"], ~w(candidate accept), :invalid_completion),
         {:ok, approver} <- approver_from_form(params, completion, owner_id),
         {:ok, fallback_approver} <- fallback_approver_from_form(params, completion, owner_id),
         {:ok, limits} <- limits_from_form(params),
         {:ok, route} <- route_from_form(params, owner_id),
         value = %{
           "gates" => gates,
           "completion" => completion,
           "approver" => approver,
           "fallback_approver" => fallback_approver,
           "route_choice" => route,
           "limits" => limits
         },
         {:ok, policy} <- Policy.new(value, context) do
      {:ok, policy.value, policy.fingerprint}
    end
  end

  def built_in_presets(owner_id, %ActorContext{} = context) do
    if trusted_owner(context, owner_id) == :ok do
      owner = principal_map(:human, owner_id)
      service = FountWeb.Actors.principal(:service) |> Principal.to_map()

      [
        {"candidate-careful", "Candidate · deliberate", preset_policy("candidate", nil, "human", 8)},
        {"owner-approval", "Owner approval", preset_policy("accept", owner, "human", 8)},
        {"service-pass", "Service approval · focused", preset_policy("accept", service, "automatic", 12)}
      ]
      |> Enum.map(fn {key, label, value} ->
        preset_row("builtin:" <> key, label, 1, value, context, "built-in")
      end)
    else
      []
    end
  end

  def presets(repo, owner_id, %ActorContext{} = context) do
    if trusted_owner(context, owner_id) == :ok do
      stored =
        case FountWeb.Store.list_policy_presets(repo, owner_id) do
          rows when is_list(rows) ->
            Enum.map(rows, fn row ->
              preset_row(
                "host:" <> row["id"] <> ":" <> Integer.to_string(row["version"]),
                row["name"],
                row["version"],
                row["policy"],
                context,
                "host"
              )
            end)

          _ ->
            []
        end

      built_in_presets(owner_id, context) ++ stored
    else
      []
    end
  end

  def save_preset(repo, owner_id, name, value, %ActorContext{} = context) do
    name = if is_binary(name), do: String.trim(name), else: ""

    with :ok <- trusted_owner(context, owner_id),
         true <- byte_size(name) in 1..80 or {:error, :invalid_preset_name},
         {:ok, policy} <- Policy.new(value, context) do
      FountWeb.Store.save_policy_preset(repo, %{
        owner_id: owner_id,
        name: name,
        policy: policy.value,
        policy_fingerprint: policy.fingerprint
      })
    end
  end

  def find_preset(repo, owner_id, reference, %ActorContext{} = context) do
    with :ok <- trusted_owner(context, owner_id) do
      case Enum.find(presets(repo, owner_id, context), &(&1["reference"] == reference)) do
        nil -> {:error, :preset_not_found}
        %{"compatible" => false} -> {:error, :preset_incompatible}
        row -> {:ok, row}
      end
    end
  end

  def build_workshop_request(model, action_id, instruction, selection, attrs \\ %{}) do
    with %{"enabled" => true} = action <- Enum.find(@action_catalog, &(&1["id"] == action_id)),
         :ok <- valid_instruction(instruction),
         {:ok, selection} <- validate_selection(model, selection),
         request = %{
           "version" => 1,
           "workflow" => action_id,
           "mode" => action["mode"],
           "base_revision_id" => model.revision.id,
           "instruction" => String.trim(instruction),
           "selection" => selection,
           "constraints" => [],
           "alternatives" => 1,
           "options" => action_options(action_id, instruction, selection, attrs)
         },
         {:ok, validated} <- FountWorkshop.Request.validate(model, request) do
      {:ok, validated}
    else
      nil -> {:error, :unsupported_run_action}
      %{"enabled" => false} -> {:error, :unsupported_run_action}
      {:error, _} = error -> error
    end
  end

  def save_selection(repo, owner_id, run, selection, %ActorContext{} = context) do
    base_revision_id = get_in(run, ["plan", "base_revision_id"])

    with :ok <- trusted_owner(context, owner_id),
         :ok <- ActorContext.authorize(context, :read_run, run["screenplay_id"]),
         {:ok, model} <- Fount.Persistence.load_revision(repo, run["screenplay_id"], base_revision_id),
         {:ok, selection} <- validate_selection(model, selection) do
      fingerprint = CanonicalJSON.hash(selection)

      case FountWeb.Store.put_workflow_selection(repo, %{
             owner_id: owner_id,
             run_id: run["id"],
             screenplay_id: run["screenplay_id"],
             base_revision_id: base_revision_id,
             selection: selection,
             selection_fingerprint: fingerprint
           }) do
        {:ok, row} -> {:ok, Map.put(row, "preview", selection_preview(model, selection))}
        error -> error
      end
    end
  end

  def load_selection(repo, owner_id, run, %ActorContext{} = context) do
    base_revision_id = get_in(run, ["plan", "base_revision_id"])

    with :ok <- trusted_owner(context, owner_id),
         :ok <- ActorContext.authorize(context, :read_run, run["screenplay_id"]),
         {:ok, row} <- FountWeb.Store.workflow_selection(repo, owner_id, run["id"]),
         true <- row["screenplay_id"] == run["screenplay_id"] or {:error, :selection_screenplay_stale},
         true <- row["base_revision_id"] == base_revision_id or {:error, :selection_base_stale},
         {:ok, model} <- Fount.Persistence.load_revision(repo, run["screenplay_id"], base_revision_id),
         {:ok, selection} <- validate_selection(model, row["selection"]) do
      {:ok, Map.merge(row, %{"selection" => selection, "preview" => selection_preview(model, selection)})}
    else
      {:error, :not_found} -> default_selection(repo, owner_id, run, context)
      {:error, _} = error -> error
      false -> {:error, :selection_stale}
    end
  end

  def selection_from_params(params) when is_map(params) do
    if truthy?(params["whole_screenplay"]) do
      {:ok, %{"whole_screenplay" => true}}
    else
      scenes = list(params["scene_ids"])
      elements = list(params["element_ids"])

      targets =
        Enum.map(scenes, &%{"kind" => "scene", "id" => &1}) ++
          Enum.map(elements, &%{"kind" => "element", "id" => &1})

      if targets == [] or length(targets) > @max_scope_targets,
        do: {:error, :invalid_scope_selection},
        else: {:ok, %{"targets" => targets}}
    end
  end

  def split_scopes(%{"whole_screenplay" => true} = selection, false), do: [selection]
  def split_scopes(selection, false), do: [selection]

  def split_scopes(%{"targets" => targets}, true)
      when is_list(targets) and length(targets) <= @max_multi_launch do
    Enum.map(targets, &%{"targets" => [&1]})
  end

  def split_scopes(%{"whole_screenplay" => true} = selection, true), do: [selection]
  def split_scopes(_, _), do: []

  def max_multi_launch, do: @max_multi_launch

  def launch_preview(model, action_id, instruction, selection, policy, multi?) do
    scopes = split_scopes(selection, multi?)

    with true <- scopes != [] and length(scopes) <= @max_multi_launch or {:error, :multi_launch_limit},
         {:ok, policy} <- ensure_policy_map(policy),
         {:ok, entries} <- preview_entries(model, action_id, instruction, scopes, policy) do
      {:ok,
       %{
         "command_id" => Fount.ID.v4(),
         "base_revision_id" => model.revision.id,
         "action" => action_id,
         "instruction" => String.trim(instruction),
         "policy" => policy,
         "entries" => entries
       }}
    end
  end

  def execute_launch_preview(owner_id, project_id, preview) when is_map(preview) do
    preview["entries"]
    |> Enum.with_index()
    |> Enum.map(fn {entry, index} ->
      command_id = preview["command_id"] <> ":" <> Integer.to_string(index)

      case FountWeb.Launch.create_action_from_base(owner_id, project_id, preview["base_revision_id"], %{
             "command_id" => command_id,
             "action" => preview["action"],
             "instruction" => preview["instruction"],
             "selection" => entry["selection"],
             "policy" => preview["policy"]
           }) do
        {:ok, %{run: run}} -> Map.merge(entry, %{"state" => "created", "run_id" => run["id"]})
        {:error, reason} -> Map.merge(entry, %{"state" => "failed", "error" => inspect(reason)})
      end
    end)
  end

  def launch_summary(results) do
    created = Enum.filter(results, &(&1["state"] == "created"))
    failed = Enum.filter(results, &(&1["state"] == "failed"))
    %{"created" => created, "failed" => failed, "partial" => created != [] and failed != []}
  end

  def lifecycle(run) do
    terminal? = run["status"] in @terminal
    paused? = not is_nil(run["pause_requested_at"])
    stopped? = not is_nil(run["stop_requested_at"]) or run["status"] == "stopped"

    %{
      "pause" => not terminal? and not paused? and not stopped?,
      "resume" => not terminal? and paused? and not stopped?,
      "stop" => not terminal? and not stopped?,
      "update_plan" => not terminal? and not stopped?,
      "update_policy" => not terminal? and not stopped?,
      "reason" => lifecycle_reason(run)
    }
  end

  def plan_update(current, goal) when is_map(current) and is_binary(goal) do
    goal = String.trim(goal)

    if goal == "" or byte_size(goal) > 2_000 do
      {:error, :invalid_goal}
    else
      {:ok,
       current
       |> Map.take(~w(screenplay_id base_revision_id goal scope constraints protected_material input_brief input_notes operation_parameters))
       |> Map.put("goal", goal)}
    end
  end

  def decision_context(progress, decision, review_binding \\ %{}) do
    step = Enum.find(progress["steps"] || [], &(&1["id"] == decision["step_id"]))
    result = if is_map(step), do: step["result"] || %{}, else: %{}
    analysis = result["analysis"]
    review = exact_review_binding(decision, review_binding)

    %{
      "analysis_lineage" => if(analysis in [nil, [], %{}], do: nil, else: analysis),
      "report_ids" => result["report_ids"] || [],
      "candidate_id" => decision["candidate_id"],
      "base_revision_id" => decision["base_revision_id"],
      "candidate_revision_id" => review["candidate_revision_id"],
      "check_set_fingerprint" => decision["check_set_fingerprint"] || review["check_set_fingerprint"]
    }
  end

  def notifications(run, progress) do
    decision_items =
      for item <- progress["decisions"] || [], item["status"] == "pending" do
        notification("decision:" <> item["id"], "decision_required", "Decision required", item["kind"] || "checkpoint")
      end

    artifact_items =
      for item <- progress["deliveries"] || [], item["state"] in ["ready", "failed"] do
        case item["state"] do
          "ready" -> notification("artifact:" <> item["id"], "artifact_ready", "Artifact ready", item["format"])
          "failed" -> notification("artifact:" <> item["id"] <> ":failed", "error", "Artifact failed", item["format"] <> ": " <> to_string(item["error"] || "delivery_failed"))
        end
      end

    step_items =
      for item <- progress["steps"] || [], item["status"] in ["failed", "error"] do
        notification("step:" <> item["id"] <> ":failed", "error", "Run step failed", item["stage"] || "step")
      end

    run_items =
      if run["status"] == "failed" do
        [notification("run:" <> run["id"] <> ":failed:" <> to_string(run["lock_version"] || 0), "error", "Run failed", "Persisted state reports failure")]
      else
        []
      end

    (decision_items ++ artifact_items ++ step_items ++ run_items)
    |> Enum.uniq_by(& &1["id"])
    |> Enum.sort_by(& &1["id"])
  end

  def list_owner_runs(repo, owner_id, opts \\ []) do
    limit = opts |> Keyword.get(:limit, @max_run_list) |> min(@max_run_list) |> max(1)

    case FountWeb.Store.list_run_accesses(repo, owner_id, limit: limit, status: Keyword.get(opts, :status)) do
      rows when is_list(rows) ->
        rows
        |> Enum.flat_map(fn access ->
          with {:ok, context} <- FountWeb.Actors.owner_context(owner_id, access["screenplay_id"]),
               {:ok, run} <- FountRun.get_run(repo, access["run_id"], context) do
            [Map.put(run, "project", Map.take(access, ~w(project_id title key screenplay_id)))]
          else
            _ -> []
          end
        end)
        |> Enum.take(limit)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  def compare_owner_runs(repo, owner_id, left_id, right_id) do
    with true <- left_id != right_id or {:error, :same_run},
         {:ok, left} <- authorized_run_snapshot(repo, owner_id, left_id),
         {:ok, right} <- authorized_run_snapshot(repo, owner_id, right_id) do
      {:ok,
       %{
         "left" => left,
         "right" => right,
         "same_screenplay" => left["screenplay_id"] == right["screenplay_id"],
         "same_base" => left["base_revision_id"] == right["base_revision_id"],
         "same_scope" => left["scope_fingerprint"] == right["scope_fingerprint"],
         "facts" => factual_deltas(left, right)
       }}
    end
  end

  def export_preview(repo, run, progress, %ActorContext{} = context) do
    candidate_id = run["selected_candidate_id"]

    with true <- is_binary(candidate_id) or {:error, :no_exportable_candidate},
         :ok <- ActorContext.authorize(context, :read_run, run["screenplay_id"]),
         {:ok, candidate} <- Fount.Persistence.candidate(repo, candidate_id),
         true <- candidate["screenplay_id"] == run["screenplay_id"] or {:error, :candidate_identity_mismatch},
         {:ok, fdx} <- Fount.Screenplay.to_fdx(candidate["screenplay"]) do
      {:ok,
       %{
         "candidate_id" => candidate_id,
         "result_revision_id" => candidate["result_revision_id"],
         "completion" => if(run["status"] == "completed_accepted", do: "accepted", else: "candidate"),
         "fountain_bytes" => byte_size(Fount.Screenplay.to_fountain(candidate["screenplay"], mode: :spec)),
         "fdx_losses" => fdx.losses,
         "delivery_count" => length(progress["deliveries"] || [])
       }}
    end
  end

  defp authorized_run_snapshot(repo, owner_id, run_id) do
    with {:ok, access} <- FountWeb.Store.run_access(repo, owner_id, run_id),
         {:ok, context} <- FountWeb.Actors.owner_context(owner_id, access["screenplay_id"]),
         {:ok, run} <- FountRun.get_run(repo, run_id, context),
         {:ok, progress} <- FountRun.progress(repo, run_id, context) do
      {:ok,
       %{
         "id" => run["id"],
         "screenplay_id" => run["screenplay_id"],
         "base_revision_id" => get_in(run, ["plan", "base_revision_id"]),
         "scope_fingerprint" => CanonicalJSON.hash(get_in(run, ["plan", "scope"])),
         "status" => run["status"],
         "stage" => run["stage"],
         "selected_candidate_id" => run["selected_candidate_id"],
         "plan_version" => run["current_plan_version"],
         "policy_version" => run["current_policy_version"],
         "resources" => progress["resources"],
         "usage_rows" => length(progress["usage"] || []),
         "delivery_rows" => length(progress["deliveries"] || [])
       }}
    end
  end

  defp factual_deltas(left, right) do
    [
      %{"field" => "status", "left" => left["status"], "right" => right["status"]},
      %{"field" => "stage", "left" => left["stage"], "right" => right["stage"]},
      %{"field" => "usage rows", "left" => left["usage_rows"], "right" => right["usage_rows"]},
      %{"field" => "delivery rows", "left" => left["delivery_rows"], "right" => right["delivery_rows"]}
    ]
  end

  defp default_selection(repo, owner_id, run, context) do
    selection = %{"whole_screenplay" => true}
    save_selection(repo, owner_id, run, selection, context)
  end

  defp validate_selection(model, %{"whole_screenplay" => true} = selection) do
    case Fount.Selection.selected_ids(model, selection) do
      {:ok, _} -> {:ok, selection}
      error -> error
    end
  end

  defp validate_selection(model, %{"targets" => targets} = selection)
       when is_list(targets) and targets != [] and length(targets) <= @max_scope_targets do
    allowed = Enum.all?(targets, &(&1["kind"] in ["scene", "element"]))

    with true <- allowed or {:error, :unsupported_scope_target},
         {:ok, _ids} <- Fount.Selection.selected_ids(model, selection) do
      {:ok, selection}
    end
  end

  defp validate_selection(_, _), do: {:error, :invalid_scope_selection}

  defp selection_preview(model, %{"whole_screenplay" => true}) do
    [%{"kind" => "screenplay", "id" => model.id, "label" => "Whole screenplay"}]
  end

  defp selection_preview(model, %{"targets" => targets}) do
    Enum.map(targets, fn target ->
      label =
        case target do
          %{"kind" => "scene", "id" => id} ->
            case Fount.Query.scene(model, id) do
              nil -> "Deleted scene"
              scene ->
                case Fount.Query.node(model, scene.heading_id) do
                  nil -> "Scene"
                  heading -> heading.text || "Scene"
                end
            end

          %{"kind" => "element", "id" => id} ->
            case Fount.Query.node(model, id) do
              nil -> "Deleted element"
              element -> "#{element.type}: " <> String.slice(element.text || "", 0, 72)
            end
        end

      Map.put(target, "label", label)
    end)
  end

  defp preview_entries(model, action_id, instruction, scopes, policy) do
    Enum.reduce_while(scopes, {:ok, []}, fn selection, {:ok, acc} ->
      case build_workshop_request(model, action_id, instruction, selection) do
        {:ok, request} ->
          entry = %{
            "selection" => selection,
            "selection_fingerprint" => CanonicalJSON.hash(selection),
            "preview" => selection_preview(model, selection),
            "budget" => policy["limits"],
            "request_fingerprint" => CanonicalJSON.hash(request)
          }

          {:cont, {:ok, [entry | acc]}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp ensure_policy_map(value) when is_map(value), do: {:ok, value}
  defp ensure_policy_map(_), do: {:error, :invalid_policy}

  defp gates_from_form(params) do
    Enum.reduce_while(@gate_keys, {:ok, %{}}, fn key, {:ok, acc} ->
      case enum(params[key], @gate_modes, {:invalid_gate, key}) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp approver_from_form(_params, "candidate", _owner_id), do: {:ok, nil}

  defp approver_from_form(params, "accept", owner_id) do
    FountWeb.Actors.resolve_policy_principal(owner_id, params["approver"])
  end

  defp fallback_approver_from_form(_params, "candidate", _owner_id), do: {:ok, nil}

  defp fallback_approver_from_form(params, "accept", owner_id) do
    if truthy?(params["owner_fallback_enabled"]) do
      FountWeb.Actors.resolve_policy_principal(owner_id, "owner")
    else
      {:ok, nil}
    end
  end

  defp limits_from_form(params) do
    with {:ok, limits} <- integer_limits(params),
         {:ok, money} <- money_from_form(params) do
      {:ok, Map.put(limits, "money", money)}
    end
  end

  defp integer_limits(params) do
    Enum.reduce_while(@limit_keys, {:ok, %{}}, fn key, {:ok, acc} ->
      case nonnegative_integer(params[key]) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        {:error, _} -> {:halt, {:error, {:invalid_limit, key}}}
      end
    end)
  end

  defp money_from_form(params) do
    if truthy?(params["money_enabled"]) do
      currency = params["currency"]

      with true <- is_binary(currency) and Regex.match?(~r/^[A-Z]{3}$/, currency) or {:error, :invalid_currency},
           {:ok, max_microunits} <- nonnegative_integer(params["max_microunits"]) do
        {:ok, %{"currency" => currency, "max_microunits" => max_microunits}}
      end
    else
      {:ok, nil}
    end
  end

  defp route_from_form(%{"route_choice" => "pause_on_material_tradeoff"}, _owner_id),
    do: {:ok, %{"rule" => "pause_on_material_tradeoff"}}

  defp route_from_form(%{"route_choice" => "registered_reviewer"} = params, owner_id) do
    with {:ok, reviewer_id} <-
           FountWeb.Actors.resolve_route_reviewer(owner_id, params["route_reviewer_key"]) do
      {:ok, %{"rule" => "registered_reviewer", "reviewer_id" => reviewer_id}}
    end
  end

  defp route_from_form(_, _owner_id), do: {:error, :invalid_route_choice}

  defp preset_policy(completion, approver, strategy_mode, inference_calls) do
    %{
      "gates" => %{
        "investigation_scope" => "automatic",
        "strategy_choice" => strategy_mode,
        "candidate_generation" => "automatic",
        "iteration" => "automatic"
      },
      "completion" => completion,
      "approver" => approver,
      "fallback_approver" => nil,
      "route_choice" => %{"rule" => "pause_on_material_tradeoff"},
      "limits" => %{
        "max_iterations" => 2,
        "max_malformed_repairs_per_call" => 1,
        "max_transient_retries" => 2,
        "max_inference_calls" => inference_calls,
        "max_measurement_states" => 500,
        "money" => nil
      }
    }
  end

  defp preset_row(reference, label, version, value, context, source) do
    case Policy.new(value, context) do
      {:ok, policy} ->
        %{
          "reference" => reference,
          "name" => label,
          "version" => version,
          "source" => source,
          "policy" => policy.value,
          "fingerprint" => policy.fingerprint,
          "compatible" => true,
          "error" => nil
        }

      {:error, reason} ->
        %{
          "reference" => reference,
          "name" => label,
          "version" => version,
          "source" => source,
          "policy" => value,
          "fingerprint" => CanonicalJSON.hash(value),
          "compatible" => false,
          "error" => inspect(reason)
        }
    end
  end

  defp action_options("develop", _instruction, _selection, _attrs), do: %{"placement" => %{"kind" => "start"}}

  defp action_options("propagate", instruction, selection, _attrs),
    do: %{"change" => String.trim(instruction), "repair_scope" => selection}

  defp action_options("pass", _instruction, _selection, attrs) do
    profile = if attrs["profile"] in ~w(dialogue_subtext action_visual sound_space cinematic_rhythm transition brevity dry_comedy tension), do: attrs["profile"], else: "dialogue_subtext"
    %{"profile" => profile}
  end

  defp valid_instruction(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed != "" and byte_size(trimmed) <= @max_instruction_bytes, do: :ok, else: {:error, :invalid_instruction}
  end

  defp valid_instruction(_), do: {:error, :invalid_instruction}

  defp exact_review_binding(decision, review_binding) do
    candidate_id = decision["candidate_id"]
    base_revision_id = decision["base_revision_id"]

    if is_binary(candidate_id) and candidate_id == review_binding["candidate_id"] and
         is_binary(base_revision_id) and base_revision_id == review_binding["base_revision_id"] do
      review_binding
    else
      %{}
    end
  end

  defp trusted_owner(%ActorContext{owner: %Principal{type: :human, id: id}}, owner_id)
       when id == owner_id,
       do: :ok

  defp trusted_owner(_context, _owner_id), do: {:error, :owner_context_mismatch}

  defp lifecycle_reason(run) do
    cond do
      run["status"] in @terminal -> "Run is terminal; restart-from-stage is not supported."
      not is_nil(run["stop_requested_at"]) -> "Run is stopped and fenced."
      not is_nil(run["pause_requested_at"]) -> "Run is paused; resume is the supported continuation."
      true -> "Current state accepts supported owner controls."
    end
  end

  defp notification(id, kind, title, detail),
    do: %{"id" => id, "kind" => kind, "title" => title, "detail" => detail}

  defp principal_map(type, id) do
    {:ok, principal} = Principal.new(type, id)
    Principal.to_map(principal)
  end

  defp enum(value, values, error), do: if(value in values, do: {:ok, value}, else: {:error, error})

  defp nonnegative_integer(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp nonnegative_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _ -> {:error, :invalid_integer}
    end
  end

  defp nonnegative_integer(_), do: {:error, :invalid_integer}
  defp list(nil), do: []
  defp list(value) when is_list(value), do: Enum.filter(value, &is_binary/1)
  defp list(value) when is_binary(value), do: [value]
  defp list(_), do: []
  defp truthy?(value), do: value in [true, "true", "on", "1"]
end
