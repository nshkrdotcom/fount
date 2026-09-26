defmodule FountProbe.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/fount"

  def project do
    [
      app: :fount_probe,
      version: @version,
      name: "FountProbe",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      description:
        "Screenplay-specific inspection, comparison, and investigation engine for the Fount framework",
      source_url: @source_url,
      homepage_url: @source_url,
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix]],
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp deps do
    [
      {:fount, "~> 0.1.0", path: "../fount"},
      {:system_one_sdk, "~> 0.5.0"},
      {:inference, "~> 0.4.0"},
      {:agent_session_manager, "~> 0.16.0"},
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "FountProbe",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      canonical: "https://hexdocs.pm/fount_probe",
      logo: "assets/fount_probe.svg",
      assets: %{"assets" => "assets"},
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "guides/architecture.md",
        "guides/tools-and-catalog.md",
        "guides/investigations-and-evidence.md",
        "guides/comparison-and-ablation.md",
        "examples/README.md"
      ],
      groups_for_extras: [
        Overview: ~r/(README|CHANGELOG|LICENSE)/,
        Guides:
          ~r/guides\/(architecture|tools-and-catalog|investigations-and-evidence|comparison-and-ablation)/,
        "Live Examples": ~r/examples/
      ],
      groups_for_modules: [
        Probe: [
          FountProbe,
          FountProbe.Catalog,
          FountProbe.Report,
          FountProbe.Investigation,
          FountProbe.Comparison
        ],
        Analysis: [
          FountProbe.Action,
          FountProbe.Action.Layout,
          FountProbe.Continuity,
          FountProbe.Constraints,
          FountProbe.Dependencies,
          FountProbe.Dialogue,
          FountProbe.Extraction,
          FountProbe.Inventory,
          FountProbe.Knowledge,
          FountProbe.KnowledgeTrace,
          FountProbe.KnowledgeTrace.Behavior,
          FountProbe.Projection,
          FountProbe.Retrieval,
          FountProbe.SceneMechanics,
          FountProbe.Search,
          FountProbe.StrategyContrast,
          FountProbe.Voice
        ],
        Support: [
          FountProbe.Access,
          FountProbe.Budget,
          FountProbe.CLI,
          FountProbe.Completion,
          FountProbe.Jev,
          FountProbe.Launcher,
          FountProbe.LiveExample,
          FountProbe.Profile,
          FountProbe.SavedRecords,
          FountProbe.State,
          FountProbe.Writing.DecisionPolicy,
          FountProbe.Writing.Evidence,
          FountProbe.Writing.Executor
        ],
        Tasks: [
          Mix.Tasks.Fount.Probe,
          Mix.Tasks.Fount.Search
        ]
      ]
    ]
  end

  defp package do
    [
      name: "fount_probe",
      maintainers: ["nshkrdotcom"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib priv guides assets examples mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end
end
