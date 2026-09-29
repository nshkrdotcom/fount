defmodule Mix.Tasks.FountWeb.Migrate do
  use Mix.Task
  @shortdoc "Runs Core, Run, then FountWeb host migrations"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    repo = Fount.Repo

    for {label, path} <- [
          {"Core", Fount.Persistence.migrations_path()},
          {"Run", FountRun.migrations_path()},
          {"host", FountWeb.Migrations.path()}
        ] do
      Mix.shell().info("Migrating #{label}: #{path}")
      Ecto.Migrator.run(repo, path, :up, all: true)
    end
  end
end
