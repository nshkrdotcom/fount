defmodule Mix.Tasks.Fount.Rebase do
  @shortdoc "Fount rebase"
  @moduledoc "Run `mix fount.rebase --help` for usage."
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("rebase", args) |> Fount.CLI.Support.finish!()
  end
end
