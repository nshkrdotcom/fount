defmodule Fount.Intelligence.MixProject do
  use Mix.Project
  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/fount"

  def project do
    [
      app: :fount_intelligence,
      version: @version,
      name: "Fount.Intelligence",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      description:
        "Evidence-grounded screenplay investigations, comparisons, and pure interpretation for writer-controlled revision",
      source_url: @source_url,
      homepage_url: @source_url,
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix]],
      docs: docs(),
      package: package()
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]

  defp deps do
    [
      workspace_dep(:fount, "~> 0.1.0", "../fount"),
      workspace_dep(:fount_observe, "~> 0.1.0", "../fount_observe"),
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp workspace_dep(name, version, path) do
    if System.get_env("FOUNT_PACKAGE_BUILD") == "1",
      do: {name, version},
      else: {name, version, path: path}
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      canonical: "https://hexdocs.pm/fount_intelligence",
      logo: "assets/fount_intelligence.svg",
      assets: %{"assets" => "assets"},
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "guides/architecture.md",
        "guides/usage.md",
        "guides/verification.md",
        "guides/story-world.md",
        "guides/temporal-and-reader.md",
        "guides/diagnosis-and-playbooks.md",
        "guides/investigations-and-evidence.md",
        "guides/comparison-and-ablation.md",
        "guides/playbook-catalog.md",
        {"examples/README.md", filename: "examples"}
      ],
      groups_for_extras: [
        Overview: ~r/(README|CHANGELOG|LICENSE)/,
        Guides: ~r/guides\//,
        Examples: ~r/examples\//
      ],
      groups_for_modules: [
        Public: [
          Fount.Intelligence,
          Fount.Intelligence.Playbooks.Registry,
          Fount.Intelligence.Playbooks.Request,
          Fount.Intelligence.Playbooks.WriterRegistry,
          Fount.Intelligence.Reporting.WriterPacket
        ],
        "Pure interpretation": [
          Fount.Intelligence.Capabilities.DecisionPolicy,
          Fount.Intelligence.Capabilities.Interpretation,
          Fount.Intelligence.Reader,
          Fount.Intelligence.Reader.Event,
          Fount.Intelligence.Reader.Reveal,
          Fount.Intelligence.Temporal,
          Fount.Intelligence.StoryWorld,
          Fount.Intelligence.StoryWorld.Records,
          Fount.Intelligence.Diagnosis,
          Fount.Intelligence.Diagnosis.Concern
        ],
        "Acquisition and reporting": [
          Fount.Intelligence.Acquisition.Measurements,
          Fount.Intelligence.Acquisition.Planner,
          Fount.Intelligence.Playbooks.WriterRunner,
          Fount.Intelligence.Reporting.Report,
          Fount.Intelligence.Runner.Architecture
        ]
      ]
    ]
  end

  defp package do
    [
      name: "fount_intelligence",
      maintainers: ["nshkrdotcom"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib guides assets examples mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end
end