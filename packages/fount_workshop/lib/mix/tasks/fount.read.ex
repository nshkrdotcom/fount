defmodule Mix.Tasks.Fount.Read do
  @shortdoc "Fount read"
  @moduledoc "Run `mix fount.read --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("read", args) |> Support.finish!()
  end
end
