defmodule Mix.Tasks.Fount.Read do
  @shortdoc "Fount read"
  @moduledoc "Run `mix fount.read --help` for usage."
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("read", args) |> Fount.CLI.Support.finish!()
  end
end
