defmodule Mix.Tasks.Fount.Outline do
  @shortdoc "Fount outline"
  @moduledoc "Run `mix fount.outline --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("outline", args) |> Support.finish!()
  end
end
