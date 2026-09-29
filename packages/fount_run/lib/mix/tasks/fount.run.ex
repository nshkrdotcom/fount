defmodule Mix.Tasks.Fount.Run do
  @shortdoc "Run the durable Fount screenplay pipeline"
  @moduledoc "Run `mix fount.run --help` for the complete headless Phase-05 command surface."
  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {code, payload} =
      case start_configured_repo() do
        :ok ->
          FountRun.CLI.run(args)

        {:error, reason} ->
          {5, %{"status" => "error", "error" => inspect(reason), "exit_code" => 5}}
      end

    output = Jason.encode!(payload, pretty: true)

    if code == 0 do
      Mix.shell().info(output)
    else
      Mix.shell().error(output)
      System.halt(code)
    end
  end

  defp start_configured_repo do
    configured = Application.get_env(:fount_run, :cli, [])

    repo =
      if is_map(configured), do: Map.get(configured, :repo), else: Keyword.get(configured, :repo)

    cond do
      not is_atom(repo) or is_nil(repo) -> :ok
      Process.whereis(repo) -> :ok
      true -> start_repo(repo)
    end
  end

  defp start_repo(repo) do
    case repo.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, _reason} -> {:error, :cli_repo_start_failed}
    end
  rescue
    _error -> {:error, :cli_repo_start_failed}
  end
end
