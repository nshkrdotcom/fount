defmodule FountRun.DispatchHook do
  @moduledoc false

  alias FountRun.ExecutionStore

  def new(repo, claim, opts \\ []) do
    ref = make_ref()

    fn
      :before, dispatch -> before_dispatch(repo, claim, ref, dispatch, opts)
      :after, dispatch -> after_dispatch(repo, ref, dispatch, opts)
      :validation, dispatch -> record_validation(repo, claim, ref, dispatch)
    end
  end

  defp before_dispatch(repo, claim, ref, dispatch, opts) do
    case ExecutionStore.provider_intent(repo, claim, dispatch) do
      {:ok, operation_id} ->
        maybe_fault(opts, :after_provider_intent)

        case ExecutionStore.provider_dispatched(repo, claim, operation_id) do
          {:ok, :ok} ->
            Process.put({__MODULE__, ref, dispatch_key(dispatch)}, operation_id)
            maybe_fault(opts, :after_provider_dispatched)
            :ok

          {:ok, {:reuse, response}} ->
            remember_validation(ref, dispatch, operation_id, opts)
            {:reuse, response}

          {:error, _} = error ->
            error
        end

      {:reuse, response, operation_id} ->
        remember_validation(ref, dispatch, operation_id, opts)
        {:reuse, response}

      {:error, _} = error ->
        error
    end
  end

  defp remember_validation(ref, dispatch, operation_id, opts) do
    if Keyword.get(opts, :audit_validation, false),
      do: Process.put({__MODULE__, ref, dispatch_key(dispatch)}, operation_id)
  end

  defp after_dispatch(repo, ref, dispatch, opts) do
    key = {__MODULE__, ref, dispatch_key(dispatch)}

    operation_id =
      if Keyword.get(opts, :audit_validation, false),
        do: Process.get(key),
        else: Process.delete(key)

    case operation_id do
      nil ->
        {:error, :provider_operation_identity_missing}

      operation_id ->
        maybe_fault(opts, :after_provider_call_before_response_persist)

        case ExecutionStore.provider_result(repo, operation_id, dispatch.result) do
          {:ok, _row} ->
            maybe_fault(opts, :after_provider_response_persisted)
            :ok

          {:error, _} = error ->
            error
        end
    end
  end

  defp record_validation(repo, claim, ref, dispatch) do
    key = {__MODULE__, ref, dispatch_key(dispatch)}

    case Process.get(key) do
      nil ->
        {:error, :provider_operation_identity_missing}

      operation_id ->
        case ExecutionStore.provider_validation(
               repo,
               claim,
               operation_id,
               dispatch.validation_result
             ) do
          {:ok, _} ->
            Process.delete(key)
            :ok

          {:error, _} = error ->
            error
        end
    end
  end

  defp dispatch_key(dispatch),
    do: {dispatch.request_sha256, dispatch.dispatch_index, Map.get(dispatch, :transport_retry, 0)}

  defp maybe_fault(opts, stage) do
    case Keyword.get(opts, :fault_injector) do
      nil -> :ok
      fun when is_function(fun, 1) -> fun.(stage)
    end
  end
end
