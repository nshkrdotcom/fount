defmodule Mix.Tasks.Fount.Architecture do
  @moduledoc "Check the four-package graph, pure Core/Shell separation, and source/compiled forbidden dependencies."
  @shortdoc "Check source and compiled architecture boundaries"
  use Mix.Task

  @impl true
  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: [source_only: :boolean, root: :string, output: :string])
    if rest != [] or invalid != [], do: Mix.raise("usage: mix fount.architecture [--source-only] [--root PATH] [--output JSON]")
    unless opts[:source_only], do: Mix.Task.run("compile", ["--warnings-as-errors"])
    root = opts[:root] || Path.expand("../..", File.cwd!())
    report = Fount.Intelligence.Runner.Architecture.check(root, source_only: opts[:source_only] || false)
    json = Jason.encode!(report, pretty: true)
    if output = opts[:output] do
      File.mkdir_p!(Path.dirname(output))
      File.write!(output, json <> "\n")
    end
    Mix.shell().info(json)
    if report["status"] != "pass", do: Mix.raise("architecture gate failed")
  end
end
