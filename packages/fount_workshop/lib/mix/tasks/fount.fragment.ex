defmodule Mix.Tasks.Fount.Fragment do
  @shortdoc "Fount fragment"
  @moduledoc "Run `mix fount.fragment --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("fragment", args) |> Support.finish!()
  end
end
