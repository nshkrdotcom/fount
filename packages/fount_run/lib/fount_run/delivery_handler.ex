defmodule FountRun.DeliveryHandler do
  @moduledoc "Durable deliver-stage adapter over the same public delivery bundle implementation."
  @behaviour FountRun.StageHandler

  @impl true
  def execute(%{"stage" => "deliver"} = claim, opts) do
    repo = Keyword.fetch!(opts, :repo)
    context = Keyword.fetch!(opts, :actor_context)

    destination =
      get_in(claim, ["request", "destination"]) || Keyword.get(opts, :delivery_destination)

    delivery_opts =
      opts
      |> Keyword.take([:artifact_root, :pdf, :pdf_options, :table_read])
      |> Keyword.put(:defer_run_completion, true)

    case FountRun.DeliveryBundle.deliver(
           repo,
           claim["run_id"],
           destination,
           context,
           delivery_opts
         ) do
      {:ok, payload} ->
        status =
          get_in(payload, ["run", "delivery_completion_status"]) || completion_status(payload)

        {:ok,
         %{
           "status" => "delivery_ready",
           "run_status" => status,
           "next_stage" => "deliver",
           "candidate_id" => get_in(payload, ["manifest", "candidate_id"]),
           "revision_id" => delivery_revision(payload),
           "manifest_location" => payload["manifest_location"],
           "report_ids" => [],
           "changes_canon" => false
         }}

      {:partial, :delivery_partial, payload} ->
        {:partial, :delivery_partial,
         %{
           "candidate_id" => get_in(payload, ["manifest", "candidate_id"]),
           "manifest_location" => payload["manifest_location"],
           "failures" => payload["failures"]
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute(_claim, _opts), do: {:error, :unsupported_delivery_stage}

  defp completion_status(payload) do
    if get_in(payload, ["manifest", "completion_kind"]) == "accepted",
      do: "completed_accepted",
      else: "completed_candidate"
  end

  defp delivery_revision(payload) do
    get_in(payload, ["manifest", "accepted_revision_id"]) ||
      get_in(payload, ["manifest", "result_revision_id"])
  end
end
