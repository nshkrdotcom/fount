defmodule FountWeb.Services do
  @moduledoc false

  def inference_client do
    case Application.get_env(:fount_web, :inference_client_factory) do
      {module, function, args} -> apply(module, function, args)
      nil -> Inference.Client.new!(adapter: FountWeb.DemoAdapter, model: "fount-phase06-demo-v1")
    end
  end

  def worker_step_opts(owner_id, screenplay_id, run) do
    base = [
      inference: inference_client(),
      lease_ms: 15_000,
      heartbeat_ms: 5_000,
      delivery_destination: Path.join("runs", run["id"]),
      artifact_root: Application.fetch_env!(:fount_web, :artifact_root)
    ]

    case get_in(run, ["policy", "policy", "approver", "type"]) do
      type when type in ["agent", "service"] ->
        kind = String.to_existing_atom(type)
        {:ok, context} = FountWeb.Actors.automated_context(kind, owner_id, screenplay_id)
        base ++ [approval_context: context, approval_callback: &automated_review/1]

      _ ->
        base
    end
  end

  def automated_review(_packet), do: %{"recommendation" => "approve", "findings" => [], "overrides" => []}
end
