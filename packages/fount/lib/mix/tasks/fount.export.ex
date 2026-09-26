defmodule Mix.Tasks.Fount.Export do
  @shortdoc "Fount export"
  @moduledoc "Run `mix fount.export --help` for usage."
  alias Fount.CLI.Support
  use Mix.Task
  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    Fount.CLI.run("export", args) |> Support.finish!()
  end
end
