defmodule Mix.Tasks.Fount.Export do
  @shortdoc "Fount export"
  @moduledoc "Run `mix fount.export --help` for usage."
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    Fount.CLI.run("export", args) |> Fount.CLI.Support.finish!()
  end
end
