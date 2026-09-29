defmodule FountRun.WorkshopIntegration do
  @moduledoc false

  alias Fount.Writing.CanonicalJSON
  alias FountRun.ExecutionStore
  alias FountWorkshop.Store

  @doc false
  def guarded_services(repo, claim, inference, opts) do
    guard = fn kind, identity -> ExecutionStore.domain_guard(repo, claim, kind, identity) end
    services = %{store: Store.new(repo, guard: guard), inference: inference}

    case Keyword.get(opts, :observe) do
      nil -> services
      observe -> Map.put(services, :observe, observe)
    end
  end

  @doc false
  def durable_analysis_options(options, claim, opts) when is_list(options) do
    case Keyword.get(opts, :observe) do
      nil ->
        options

      _observe ->
        options
        |> Keyword.put(:durable_analysis, true)
        |> Keyword.put(:analysis_privacy_namespace, privacy_namespace(claim))
    end
  end

  @doc false
  def privacy_namespace(%{"screenplay_id" => screenplay_id}) when is_binary(screenplay_id) do
    "fount-run:screenplay:" <>
      CanonicalJSON.hash(%{"screenplay_id" => screenplay_id})
  end
end
