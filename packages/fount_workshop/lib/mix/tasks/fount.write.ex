defmodule Mix.Tasks.Fount.Write do
  @shortdoc "Fount write"
  @moduledoc "Run `mix fount.write --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("write", args) |> Support.finish!()
  end
end
