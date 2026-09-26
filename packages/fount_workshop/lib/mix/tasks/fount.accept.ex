defmodule Mix.Tasks.Fount.Accept do
  @shortdoc "Fount accept"
  @moduledoc "Run `mix fount.accept --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("accept", args) |> Support.finish!()
  end
end
