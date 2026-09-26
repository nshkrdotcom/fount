defmodule Mix.Tasks.Fount.Materialize do
  @shortdoc "Fount materialize"
  @moduledoc "Run `mix fount.materialize --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("materialize", args) |> Support.finish!()
  end
end
