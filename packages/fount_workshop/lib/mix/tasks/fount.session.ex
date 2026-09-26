defmodule Mix.Tasks.Fount.Session do
  @shortdoc "Fount session"
  @moduledoc "Run `mix fount.session --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("session", args) |> Support.finish!()
  end
end
