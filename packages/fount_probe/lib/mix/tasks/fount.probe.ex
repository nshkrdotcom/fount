defmodule Mix.Tasks.Fount.Probe do
  @shortdoc "Fount probe"
  @moduledoc "Run `mix fount.probe --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountProbe.CLI.run("probe", args) |> Support.finish!()
  end
end
