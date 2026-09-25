defmodule Mix.Tasks.Fount.Inspect do
  @shortdoc "Fount inspect"
  @moduledoc "Run `mix fount.inspect --help` for usage."
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    Fount.CLI.run("inspect", args) |> Fount.CLI.Support.finish!()
  end
end
