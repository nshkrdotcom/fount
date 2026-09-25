defmodule Mix.Tasks.Fount.History do
  @shortdoc "Fount history"
  @moduledoc "Run `mix fount.history --help` for usage."
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    Fount.CLI.run("history", args) |> Fount.CLI.Support.finish!()
  end
end
