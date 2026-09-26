defmodule Mix.Tasks.Fount.Render do
  @shortdoc "Fount render"
  @moduledoc "Run `mix fount.render --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("render", args) |> Support.finish!()
  end
end
