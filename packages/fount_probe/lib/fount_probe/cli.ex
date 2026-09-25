defmodule FountProbe.CLI do
  @moduledoc "Catalog-validated inspection requests and literal/history search."
  alias Fount.CLI.Support, as: S

  def run(command, argv) do
    with {:ok, opts, []} <-
           S.parse(argv,
             key: :string,
             request: :string,
             output: :string,
             query: :string,
             history: :boolean,
             revision: :string
           ) do
      if opts[:help] do
        {:ok,
         %{
           "usage" =>
             "mix fount.#{command} --key KEY #{if command == "search", do: "--query TEXT [--history]", else: "--request requests.json"} --output DIRECTORY"
         }}
      else
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
               FountProbe.Launcher.clients(
                 inference: command != "search",
                 jev: command != "search"
               ),
             {:ok, reports} <-
               FountProbe.execute(model, requests, clients,
                 report_reader: fn id -> Fount.Persistence.report(repo, id) end,
                 history_reader: fn sid, rid ->
                   Fount.Persistence.load_revision(repo, sid, rid)
                 end
               ),
             {:ok, saved} <- save(reports, repo, opts[:output]) do
          if Enum.all?(reports, &(&1.status == "complete")),
            do: {:ok, saved},
            else: {:error, :partial_probe_report}
        end
      end
    else
      {:ok, _, _} -> {:error, :unexpected_positional_arguments}
      error -> error
    end
  end

  defp requests("probe", _, _, opts), do: S.json_file(opts[:request])

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
         "tool" => "search",
         "params" => %{
           "query" => opts[:query],
           "revision_ids" => revisions,
           "exact_phrase" => true,
           "mode" => "inspect_all"
         }
       }
     ]}
  end

  def validate_requests(model, requests) when is_list(requests) do
    Enum.reduce_while(requests, :ok, fn req, :ok ->
      result =
        if is_map(req) and Map.keys(req) -- ~w(id tool params) == [] and is_binary(req["id"]),
          do: FountProbe.Catalog.validate(model, req["tool"], req["params"]),
          else: {:error, :invalid_probe_request}

      if result == :ok, do: {:cont, :ok}, else: {:halt, result}
    end)
  end

  def validate_requests(_, _), do: {:error, :request_array_required}

  def save(reports, repo, output) do
    Enum.reduce_while(reports, {:ok, []}, fn report, {:ok, acc} ->
      with {:ok, _} <-
             Fount.Persistence.save_report(repo, FountProbe.Report.persistence(report),
               source_models: report.transient_models
             ),
           {:ok, path} <-
             S.write_json(
               Path.join(output, report.id <> ".json"),
               FountProbe.Report.to_map(report)
             ) do
        {:cont, {:ok, acc ++ [%{"id" => report.id, "path" => path, "status" => report.status}]}}
      else
        error -> {:halt, error}
      end
    end)
  end
end
