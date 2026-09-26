defmodule Mix.Tasks.Fount.Rebase do
  @shortdoc "Fount rebase"
  @moduledoc "Run `mix fount.rebase --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("rebase", args) |> Support.finish!()
  end
end
