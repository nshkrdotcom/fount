defmodule Mix.Tasks.Fount.Audition do
  @shortdoc "Fount audition"
  @moduledoc "Run `mix fount.audition --help` for usage."
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("audition", args) |> Fount.CLI.Support.finish!()
  end
end
