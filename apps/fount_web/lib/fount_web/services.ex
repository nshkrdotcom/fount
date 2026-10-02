defmodule FountWeb.Services do
  @moduledoc false

  alias Fount.Observe.Sandbox

  @scene_engine_answers %{
    "objective" => 0.9,
    "opposition" => 0.9,
    "stakes" => 0.9,
    "urgency" => 0.9,
    "tactic" => 0.9,
    "tactic_shift" => 0.9,
    "reveal" => 0.9,
    "decision" => 0.9,
    "consequence" => 0.9,
    "value_delta" => 0.9,
    "relationship_delta" => 0.9,
    "preamble_candidate" => 0.1,
    "linger_candidate" => 0.1
  }

  @revision_intelligence_answers %{
    "intended_effect_present" => 0.9,
    "protected_strength_preserved" => 0.9,
    "continuity_risk" => 0.1,
    "knowledge_risk" => 0.1,
    "causal_risk" => 0.1,
    "voice_drift" => 0.1,
    "action_readability_risk" => 0.1,
    "setup_payoff_break" => 0.1,
    "reader_state_regression" => 0.1
  }

  def inference_client do
    case Application.get_env(:fount_web, :inference_client_factory) do
      {module, function, args} -> apply(module, function, args)
      nil -> Inference.Client.new!(adapter: FountWeb.DemoAdapter, model: "fount-phase06-demo-v1")
    end
  end

  @doc "Returns the configured analytical-host mode without exposing provider options or credentials."
  def analysis_mode do
    case observe_config() do
      {:ok, mode, _config} -> mode
      {:error, _reason} -> :invalid
    end
  end

  defp creative_worker_step_opts(owner_id, screenplay_id, run) do
    with {:ok, observe} <- observe_provider(screenplay_id, run) do
      base =
        [
          inference: inference_client(),
          lease_ms: 15_000,
          heartbeat_ms: 5_000,
          delivery_destination: Path.join("runs", run["id"]),
          artifact_root: Application.fetch_env!(:fount_web, :artifact_root)
        ]
        |> maybe_put_observe(observe)

      with {:ok, approval_opts} <- approval_opts(owner_id, screenplay_id, run) do
        {:ok, base ++ approval_opts}
      end
    end
  end

  @doc "Returns a secret-free UI summary of the analytical-host configuration."
  def analysis_service_summary do
    case analysis_mode() do
      :sandbox ->
        %{"mode" => "sandbox", "label" => "Deterministic Sandbox", "configured" => true}

      :system_one ->
        %{"mode" => "system_one", "label" => "System One", "configured" => true}

      :compatibility ->
        %{
          "mode" => "compatibility",
          "label" => "Compatibility (analysis not run)",
          "configured" => false
        }

      :invalid ->
        %{"mode" => "invalid", "label" => "Invalid analysis configuration", "configured" => false}
    end
  end

  @doc "Builds the host-owned Observe service. Provider handles stay process-local and are never persisted."
  def observe_provider(screenplay_id, run) when is_binary(screenplay_id) and is_map(run) do
    case observe_config() do
      {:ok, :sandbox, _config} -> sandbox_provider(screenplay_id, run)
      {:ok, :system_one, config} -> system_one_provider(config)
      {:ok, :compatibility, _config} -> {:ok, nil}
      {:error, _reason} -> {:error, :observe_configuration_invalid}
    end
  end

  def observe_provider(_, _), do: {:error, :observe_configuration_invalid}

  def worker_step_opts(owner_id, screenplay_id, run) do
    if semantic_run?(run) do
      semantic_worker_step_opts(owner_id, run)
    else
      creative_worker_step_opts(owner_id, screenplay_id, run)
    end
  end

  @doc "Returns a secret-free, provider-free preflight summary for SI02 assessment controls."
  def assessment_service_summary do
    case semantic_assessment_config() do
      {:ok, :disabled, _config} ->
        %{
          "mode" => "disabled",
          "label" => "Not configured",
          "configured" => false,
          "model" => FountWorkshop.SemanticAssessment.model(),
          "reasoning_effort" =>
            Atom.to_string(FountWorkshop.SemanticAssessment.reasoning_effort()),
          "reason" => "semantic assessment is disabled"
        }

      {:ok, :codex, config} ->
        cli_path = Keyword.get(config, :cli_path, "codex")

        case FountWorkshop.SemanticAssessment.preflight(
               cli_path: cli_path,
               auth_asserted: Keyword.get(config, :auth_asserted, false)
             ) do
          {:ok, _} ->
            %{
              "mode" => "codex",
              "label" => "Codex",
              "configured" => true,
              "model" => FountWorkshop.SemanticAssessment.model(),
              "reasoning_effort" =>
                Atom.to_string(FountWorkshop.SemanticAssessment.reasoning_effort()),
              "provider_family" => "codex"
            }

          {:error, reason} ->
            %{
              "mode" => "codex",
              "label" => "Codex unavailable",
              "configured" => false,
              "model" => FountWorkshop.SemanticAssessment.model(),
              "reasoning_effort" =>
                Atom.to_string(FountWorkshop.SemanticAssessment.reasoning_effort()),
              "reason" => semantic_reason(reason)
            }
        end

      {:ok, :deterministic_fixture, config} ->
        configured = valid_fixture_factory?(Keyword.get(config, :client_factory))

        %{
          "mode" => "deterministic_fixture",
          "label" => "Deterministic fixture",
          "configured" => configured,
          "model" => FountWorkshop.SemanticAssessment.model(),
          "reasoning_effort" =>
            Atom.to_string(FountWorkshop.SemanticAssessment.reasoning_effort()),
          "provider_family" => "fixture",
          "reason" => if(configured, do: nil, else: "fixture client is not configured")
        }

      {:error, reason} ->
        %{
          "mode" => "invalid",
          "label" => "Invalid assessment configuration",
          "configured" => false,
          "model" => FountWorkshop.SemanticAssessment.model(),
          "reasoning_effort" =>
            Atom.to_string(FountWorkshop.SemanticAssessment.reasoning_effort()),
          "reason" => semantic_reason(reason)
        }
    end
  end

  def assessment_client do
    case semantic_assessment_config() do
      {:ok, :codex, config} ->
        cli_path = Keyword.get(config, :cli_path, "codex")
        auth_asserted = Keyword.get(config, :auth_asserted, false)

        with {:ok, _} <-
               FountWorkshop.SemanticAssessment.preflight(
                 cli_path: cli_path,
                 auth_asserted: auth_asserted
               ) do
          FountWorkshop.SemanticAssessment.build_client(cli_path: cli_path)
        end

      {:ok, :deterministic_fixture, config} ->
        fixture_client(Keyword.get(config, :client_factory))

      {:ok, :disabled, _} ->
        {:error, :semantic_assessment_not_configured}

      {:error, _} ->
        {:error, :semantic_assessment_configuration_invalid}
    end
  end

  defp semantic_worker_step_opts(owner_id, run) do
    with {:ok, client} <- assessment_client() do
      callback = fn
        :status, payload ->
          FountWeb.SemanticStore.update_assessment_status(
            Fount.Repo,
            owner_id,
            payload["assessment_id"],
            payload["status"],
            payload["error"],
            run["id"]
          )

        :progress, payload ->
          FountWeb.SemanticStore.update_assessment_progress(
            Fount.Repo,
            owner_id,
            payload["assessment_id"],
            payload["coverage"] || %{},
            run["id"]
          )

        :result, payload ->
          FountWeb.SemanticStore.persist_assessment_result(Fount.Repo, owner_id, payload)
      end

      {:ok,
       [
         inference: client,
         semantic_store: callback,
         lease_ms: 15_000,
         heartbeat_ms: 5_000,
         artifact_root: Application.fetch_env!(:fount_web, :artifact_root)
       ]}
    end
  end

  defp semantic_run?(run),
    do: get_in(run, ["plan", "operation_parameters", "workflow"]) == "semantic_import_v2"

  defp semantic_assessment_config do
    case Application.fetch_env(:fount_web, :semantic_assessment) do
      {:ok, config} when is_list(config) ->
        semantic_config_mode(config)

      _ ->
        {:error, :missing_config}
    end
  end

  defp semantic_config_mode(config) do
    if Keyword.keyword?(config),
      do: configured_semantic_mode(config),
      else: {:error, :missing_config}
  end

  defp configured_semantic_mode(config) do
    case Keyword.get(config, :mode) do
      mode when mode in [:disabled, :codex, :deterministic_fixture] -> {:ok, mode, config}
      _ -> {:error, :invalid_mode}
    end
  end

  defp valid_fixture_factory?({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args),
       do: true

  defp valid_fixture_factory?(_), do: false

  defp fixture_client({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args) do
    case apply(module, function, args) do
      {:ok, client} -> {:ok, client}
      client when is_map(client) or is_struct(client) -> {:ok, client}
      _ -> {:error, :semantic_fixture_client_invalid}
    end
  rescue
    _ -> {:error, :semantic_fixture_client_invalid}
  end

  defp fixture_client(_), do: {:error, :semantic_fixture_client_invalid}

  defp semantic_reason(reason) when is_atom(reason),
    do: Atom.to_string(reason) |> String.replace("_", " ")

  defp semantic_reason(_), do: "assessment preflight failed"

  defp approval_opts(owner_id, screenplay_id, run) do
    case get_in(run, ["policy", "policy", "approver", "type"]) do
      type when type in ["agent", "service"] ->
        kind = String.to_existing_atom(type)

        with {:ok, context} <- FountWeb.Actors.automated_context(kind, owner_id, screenplay_id) do
          {:ok, [approval_context: context, approval_callback: &automated_review/1]}
        end

      _ ->
        {:ok, []}
    end
  end

  def automated_review(_packet),
    do: %{"recommendation" => "approve", "findings" => [], "overrides" => []}

  defp observe_config do
    case Application.fetch_env(:fount_web, :observe) do
      {:ok, config} when is_list(config) -> validate_observe_config(config)
      _ -> {:error, :missing_config}
    end
  end

  defp validate_observe_config(config) do
    if Keyword.keyword?(config) do
      case Keyword.get(config, :mode) do
        mode when mode in [:sandbox, :system_one, :compatibility] -> {:ok, mode, config}
        _ -> {:error, :invalid_mode}
      end
    else
      {:error, :invalid_config}
    end
  end

  defp system_one_provider(config) do
    provider_opts = Keyword.get(config, :provider_opts, [])

    if Keyword.keyword?(provider_opts) do
      case Fount.Observe.provider(provider_opts) do
        {:ok, provider} -> {:ok, provider}
        {:error, _error} -> {:error, :observe_provider_invalid}
      end
    else
      {:error, :observe_configuration_invalid}
    end
  rescue
    _ -> {:error, :observe_provider_invalid}
  catch
    _, _ -> {:error, :observe_provider_invalid}
  end

  defp sandbox_provider(screenplay_id, run) do
    revision_id = get_in(run, ["plan", "base_revision_id"])

    with revision_id when is_binary(revision_id) <- revision_id,
         {:ok, root} <- Fount.Persistence.load_revision(Fount.Repo, screenplay_id, revision_id) do
      fixtures =
        Enum.reduce(root.ir.scenes, %{}, fn scene, acc ->
          acc
          |> Map.put(
            "capability:scene_engine:scene:#{scene.id}",
            @scene_engine_answers
          )
          |> Map.put(
            "capability:revision_intelligence:scene:#{scene.id}",
            @revision_intelligence_answers
          )
        end)

      {:ok, Sandbox.new!(fixtures)}
    else
      _ -> {:error, :observe_sandbox_unavailable}
    end
  rescue
    _ -> {:error, :observe_sandbox_unavailable}
  end

  defp maybe_put_observe(opts, nil), do: opts
  defp maybe_put_observe(opts, observe), do: Keyword.put(opts, :observe, observe)
end
