defmodule Mix.Tasks.Fount.Import do
  @shortdoc "Fount import"
  @moduledoc "Run `mix fount.import --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    Fount.CLI.run("import", args) |> Support.finish!()
  end
end
