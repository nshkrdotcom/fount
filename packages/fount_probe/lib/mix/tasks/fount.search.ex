defmodule Mix.Tasks.Fount.Search do
  @shortdoc "Fount search"
  @moduledoc "Run `mix fount.search --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountProbe.CLI.run("search", args) |> Support.finish!()
  end
end
