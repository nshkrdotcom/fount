defmodule Mix.Tasks.Fount.Decide do
  @shortdoc "Fount decide"
  @moduledoc "Run `mix fount.decide --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    FountWorkshop.CLI.run("decide", args) |> Support.finish!()
  end
end
