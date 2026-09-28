defmodule Mix.Tasks.Fount.Edit do
  @shortdoc "Fount edit"
  @moduledoc "Run `mix fount.edit --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("edit", args) |> Support.finish!()
  end
end
