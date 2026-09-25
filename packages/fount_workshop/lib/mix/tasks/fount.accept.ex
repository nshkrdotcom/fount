defmodule Mix.Tasks.Fount.Accept do
  @shortdoc "Fount accept"
  @moduledoc "Run `mix fount.accept --help` for usage."
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("accept", args) |> Fount.CLI.Support.finish!()
  end
end
