defmodule Mix.Tasks.Fount.Materialize do
  @shortdoc "Fount materialize"
  @moduledoc "Run `mix fount.materialize --help` for usage."
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("materialize", args) |> Fount.CLI.Support.finish!()
  end
end
