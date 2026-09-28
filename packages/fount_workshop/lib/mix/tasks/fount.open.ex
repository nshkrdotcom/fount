defmodule Mix.Tasks.Fount.Open do
  @shortdoc "Fount open"
  @moduledoc "Run `mix fount.open --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("open", args) |> Support.finish!()
  end
end
