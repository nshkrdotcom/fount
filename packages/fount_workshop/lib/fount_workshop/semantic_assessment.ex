defmodule FountWorkshop.SemanticAssessment do
  @moduledoc "Host-neutral SI02 completion bridge through the existing Inference/ASM contracts."

  alias Fount.Intelligence.ImportAssessment
  alias FountWorkshop.Writing.Completion

  @model "gpt-6.1-sol"
  @effort :low

  def model, do: @model
  def reasoning_effort, do: @effort

  def build_client(opts \\ []) do
    cli = Keyword.get(opts, :cli_path, "codex")

    with :ok <- exact_policy(opts),
         {:ok, client} <-
           Inference.Client.agent_session(%{
             adapter: Inference.Adapters.ASM,
             provider: :codex,
             model: @model,
             adapter_opts: [
               query_opts: [model: @model, reasoning_effort: @effort, cli_path: cli],
               session_opts: [provider: :codex, model: @model, reasoning_effort: @effort, cli_path: cli]
             ],
             metadata: %{purpose: :fount_semantic_import}
           }),
         :ok <- Inference.Client.validate_adapter_kind(client) do
      {:ok, client}
    end
  end

  @doc "Validates the configured lane without dispatching a provider request."
  def preflight(opts \\ []) do
    cli = Keyword.get(opts, :cli_path, "codex")

    with :ok <- exact_policy(opts),
         {:ok, preflight} <-
           ASM.Options.preflight(:codex, model: @model, cli_path: cli),
         true <- preflight.common.model == @model or {:error, :semantic_model_policy_mismatch},
         true <- executable?(cli) or {:error, :codex_executable_unavailable},
         {:ok, runtime_auth} <-
           ASM.RuntimeAuth.new("fount-semantic-preflight", :codex,
             provider_account_status: if(Keyword.get(opts, :auth_asserted, false), do: :asserted, else: :unknown),
             provider_account_evidence: %{host_authorization_asserted: Keyword.get(opts, :auth_asserted, false)}
           ),
         true <- auth_available?(runtime_auth) or {:error, :codex_auth_unavailable},
         {:ok, _client} <- build_client(opts) do
      {:ok, %{model: @model, reasoning_effort: @effort, provider: :codex, executable: cli}}
    else
      {:error, _} = error -> error
      false -> {:error, :semantic_assessment_preflight_failed}
      other -> {:error, {:semantic_assessment_preflight_failed, safe(other)}}
    end
  rescue
    _ -> {:error, :semantic_assessment_preflight_failed}
  catch
    _, _ -> {:error, :semantic_assessment_preflight_failed}
  end

  def extract(client, chunk, binding, opts \\ []) do
    prompt = ImportAssessment.extraction_prompt(chunk, binding)

    Completion.complete(
      client,
      prompt,
      ImportAssessment.schema(),
      &ImportAssessment.validate_chunk(&1, chunk, binding),
      completion_opts(opts, "semantic_import_chunk")
    )
  end

  def reconcile(client, chunk_results, opts \\ []) do
    with {:ok, prompt} <- ImportAssessment.reconciliation_prompt(chunk_results),
         result <-
           Completion.complete(
             client,
             prompt,
             ImportAssessment.reconciliation_schema(),
             &ImportAssessment.validate_reconciliation(&1, chunk_results),
             completion_opts(opts, "semantic_import_reconcile")
           ) do
      result
    end
  end

  defp completion_opts(opts, name) do
    [
      name: name,
      decode_repairs: 1,
      max_context_bytes: Keyword.get(opts, :max_context_bytes, 100_000),
      budget: Keyword.get(opts, :budget),
      dispatch_hook: Keyword.get(opts, :dispatch_hook),
      transient_retries: Keyword.get(opts, :transient_retries, 0),
      reserved_cost_microunits: Keyword.get(opts, :reserved_cost_microunits),
      currency: Keyword.get(opts, :currency)
    ]
  end

  defp exact_policy(opts) do
    model = Keyword.get(opts, :model, @model)
    effort = Keyword.get(opts, :reasoning_effort, @effort)
    if model == @model and effort == @effort, do: :ok, else: {:error, :semantic_model_policy_mismatch}
  end

  defp executable?(path) when is_binary(path) do
    if Path.type(path) == :absolute, do: File.regular?(path), else: not is_nil(System.find_executable(path))
  end

  defp auth_available?(runtime_auth) do
    metadata = ASM.RuntimeAuth.to_map(runtime_auth)
    status = get_in(metadata, [:provider_account_identity, :identity_status])
    status in [:known, :asserted]
  end

  defp safe({tag, _}) when is_atom(tag), do: tag
  defp safe(%{__struct__: module}), do: module
  defp safe(value) when is_atom(value), do: value
  defp safe(_), do: :error
end
