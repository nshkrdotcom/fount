defmodule FountWorkshop.InspectionCLI do
  @moduledoc "Catalog-validated inspection requests and literal/history search."
  alias Fount.CLI.Support, as: S

  def run(command, argv) do
    case S.parse(argv,
           key: :string,
           request: :string,
           output: :string,
           query: :string,
           history: :boolean,
           revision: :string
         ) do
      {:ok, opts, []} ->
        if opts[:help] do
          {:ok,
           %{
             "usage" =>
               "mix fount.#{command} --key KEY #{if command == "search", do: "--query TEXT [--history]", else: "--request requests.json"} --output DIRECTORY"
           }}
        else
          execute_command(command, opts)
        end

      {:ok, _, _} ->
        {:error, :unexpected_positional_arguments}

      error ->
        error
    end
  end

  defp execute_command(command, opts) do
    with :ok <-
           S.required(
             opts,
             [:key, :output] ++ if(command == "search", do: [:query], else: [:request])
           ),
         {:ok, repo} <- S.connect(),
         {:ok, model} <- S.load(repo, opts),
         {:ok, requests} <- requests(command, model, repo, opts),
         :ok <- validate_requests(model, requests),
         {:ok, clients} <-
           FountWorkshop.Launcher.clients(
             inference: command != "search",
             observe: command != "search"
           ),
         {:ok, reports} <-
           Fount.Intelligence.execute(model, requests, FountWorkshop.Services.analysis(clients),
             report_reader: fn id -> Fount.Persistence.report(repo, id) end,
             history_reader: fn sid, rid ->
               Fount.Persistence.load_revision(repo, sid, rid)
             end
           ),
         {:ok, saved} <- save(reports, repo, opts[:output]) do
      complete_result(reports, saved)
    end
  end

  defp complete_result(reports, saved) do
    if Enum.all?(reports, &(&1.status == "complete")),
      do: {:ok, saved},
      else: {:error, :partial_analysis_report}
  end

  defp requests("analyze", _, _, opts), do: S.json_file(opts[:request])

  defp requests("search", model, repo, opts) do
    revisions =
      if opts[:history] do
        Fount.Persistence.history(repo, model.id) |> Enum.map(& &1.id)
      else
        [model.revision.id]
      end

    {:ok,
     [
       %{
         "id" => "literal-search",
         "playbook" => "search",
         "params" => %{
           "query" => opts[:query],
           "revision_ids" => revisions,
           "exact_phrase" => true,
           "mode" => "inspect_all"
         }
       }
     ]}
  end

  def validate_requests(model, requests) do
    case Fount.Intelligence.Playbooks.Request.parse_many(model, requests) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  def save(reports, repo, output) do
    Enum.reduce_while(reports, {:ok, []}, fn report, {:ok, acc} ->
      with {:ok, _} <-
             Fount.Persistence.save_report(repo, Fount.Intelligence.Reporting.Report.persistence(report),
               source_models: report.transient_models
             ),
           {:ok, path} <-
             S.write_json(
               Path.join(output, report.id <> ".json"),
               Fount.Intelligence.Reporting.Report.to_map(report)
             ) do
        {:cont, {:ok, acc ++ [%{"id" => report.id, "path" => path, "status" => report.status}]}}
      else
        error -> {:halt, error}
      end
    end)
  end
end
