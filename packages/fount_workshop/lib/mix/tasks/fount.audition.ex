defmodule Mix.Tasks.Fount.Audition do
  @shortdoc "Fount audition"
  @moduledoc "Run `mix fount.audition --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("audition", args) |> Support.finish!()
  end
end
