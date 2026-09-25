defmodule Mix.Tasks.Fount.Session do
  @shortdoc "Fount session"
  @moduledoc "Run `mix fount.session --help` for usage."
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("session", args) |> Fount.CLI.Support.finish!()
  end
end
