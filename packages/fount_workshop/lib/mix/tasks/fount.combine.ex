defmodule Mix.Tasks.Fount.Combine do
  @shortdoc "Fount combine"
  @moduledoc "Run `mix fount.combine --help` for usage."
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("combine", args) |> Fount.CLI.Support.finish!()
  end
end
