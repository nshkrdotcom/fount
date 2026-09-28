defmodule Mix.Tasks.Fount.Mode do
  @shortdoc "Fount mode"
  @moduledoc "Run `mix fount.mode --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("mode", args) |> Support.finish!()
  end
end
