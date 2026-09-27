defmodule Mix.Tasks.Fount.Analyze do
  @shortdoc "Inspect a screenplay"
  @moduledoc "Run `mix fount.analyze --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.InspectionCLI.run("analyze", args) |> Support.finish!()
  end
end
