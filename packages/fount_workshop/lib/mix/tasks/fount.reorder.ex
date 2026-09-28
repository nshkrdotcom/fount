defmodule Mix.Tasks.Fount.Reorder do
  @shortdoc "Fount reorder"
  @moduledoc "Run `mix fount.reorder --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("reorder", args) |> Support.finish!()
  end
end
