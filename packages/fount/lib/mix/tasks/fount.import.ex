defmodule Mix.Tasks.Fount.Import do
  @shortdoc "Fount import"
  @moduledoc "Run `mix fount.import --help` for usage."
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    Fount.CLI.run("import", args) |> Fount.CLI.Support.finish!()
  end
end
