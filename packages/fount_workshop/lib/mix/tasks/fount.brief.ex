defmodule Mix.Tasks.Fount.Brief do
  @shortdoc "Fount brief"
  @moduledoc "Run `mix fount.brief --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("brief", args) |> Support.finish!()
  end
end
