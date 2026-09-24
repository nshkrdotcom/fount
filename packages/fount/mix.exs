defmodule Fount.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/fount"

  def project do
    [
      app: :fount,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description: "Headless, lossless Fountain and screenplay framework",
      source_url: @source_url,
      homepage_url: @source_url,
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp deps do
    [
      {:jason, "~> 1.4.5"},
      {:saxy, "~> 1.6"},
      {:exqlite, "~> 0.40", optional: true},
      {:stream_data, "~> 1.4", only: :test},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "guides/architecture.md",
        "guides/lossless-fountain.md",
        "guides/ir.md",
        "guides/editing.md",
        "guides/annotations-and-analysis.md",
        "guides/persistence.md",
        "guides/adapters.md",
        "guides/research.md"
      ],
      groups_for_extras: [
        "Design": ~r/guides\/(architecture|lossless-fountain|ir|editing)/,
        "Capabilities": ~r/guides\/(annotations-and-analysis|persistence|adapters)/,
        "Research": ~r/guides\/research/
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ["lib", "guides", "mix.exs", "README.md", "CHANGELOG.md", "LICENSE"]
    ]
  end
end
