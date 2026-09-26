defmodule Mix.Tasks.Fount.History do
  @shortdoc "Fount history"
  @moduledoc "Run `mix fount.history --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    Fount.CLI.run("history", args) |> Support.finish!()
  end
end
