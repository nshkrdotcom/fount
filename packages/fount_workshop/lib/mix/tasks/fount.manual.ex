defmodule Mix.Tasks.Fount.Manual do
  @shortdoc "Fount manual"
  @moduledoc "Run `mix fount.manual --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("manual", args) |> Support.finish!()
  end
end
