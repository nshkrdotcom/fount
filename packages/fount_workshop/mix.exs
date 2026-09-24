defmodule FountWorkshop.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/fount"

  def project do
    [
      app: :fount_workshop,
      version: @version,
      name: "FountWorkshop",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description:
        "Writer revision workshop, agent loop, and PDF export for the Fount screenplay framework",
      source_url: @source_url,
      homepage_url: @source_url,
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:fount, "~> 0.1.0", path: "../fount"},
      {:inference, "~> 0.4.1"},
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "FountWorkshop",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      canonical: "https://hexdocs.pm/fount_workshop",
      logo: "assets/fount_workshop.svg",
      assets: %{"assets" => "assets"},
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Overview: ~r/(README|CHANGELOG|LICENSE)/
      ],
      groups_for_modules: [
        Workshop: [
          FountWorkshop,
          FountWorkshop.Proposal,
          FountWorkshop.Preview,
          FountWorkshop.Acceptance,
          FountWorkshop.TableRead
        ],
        Export: [
          FountWorkshop.Export.PDF,
          FountWorkshop.Submission
        ]
      ]
    ]
  end

  defp package do
    [
      name: "fount_workshop",
      maintainers: ["nshkrdotcom"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib assets mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end
end
