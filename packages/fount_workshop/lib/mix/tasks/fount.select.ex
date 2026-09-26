defmodule Mix.Tasks.Fount.Select do
  @shortdoc "Fount select"
  @moduledoc "Run `mix fount.select --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("select", args) |> Support.finish!()
  end
end
