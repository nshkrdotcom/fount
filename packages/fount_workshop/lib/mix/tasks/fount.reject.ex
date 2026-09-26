defmodule Mix.Tasks.Fount.Reject do
  @shortdoc "Fount reject"
  @moduledoc "Run `mix fount.reject --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("reject", args) |> Support.finish!()
  end
end
