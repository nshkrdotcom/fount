defmodule Mix.Tasks.Fount.Search do
  @shortdoc "Fount search"
  @moduledoc "Run `mix fount.search --help` for usage."
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountProbe.CLI.run("search", args) |> Fount.CLI.Support.finish!()
  end
end
