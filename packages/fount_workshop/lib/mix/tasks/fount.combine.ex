defmodule Mix.Tasks.Fount.Combine do
  @shortdoc "Fount combine"
  @moduledoc "Run `mix fount.combine --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("combine", args) |> Support.finish!()
  end
end
