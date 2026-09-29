defmodule Mix.Tasks.Fount.Run do
  @shortdoc "Run the durable Fount screenplay pipeline"
  @moduledoc "Run `mix fount.run --help` for the complete headless Phase-05 command surface."
  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    {code, payload} = FountRun.CLI.run(args)
    output = Jason.encode!(payload, pretty: true)

    if code == 0 do
      Mix.shell().info(output)
    else
      Mix.shell().error(output)
      System.halt(code)
    end
  end
end
