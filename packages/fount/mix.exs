defmodule Fount.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/fount"

  def project do
    [
      app: :fount,
      version: @version,
      name: "Fount",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description:
        "Headless screenplay framework with a typed model, lossless Fountain import, and relational persistence",
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
      {:jason, "~> 1.4.5"},
      {:saxy, "~> 1.6"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.20"},
      {:stream_data, "~> 1.4", only: :test},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "Fount",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      canonical: "https://hexdocs.pm/fount",
      logo: "assets/fount.svg",
      assets: %{"assets" => "assets"},
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "guides/architecture.md",
        "guides/lossless-fountain.md",
        "guides/ir.md",
        "guides/cast-and-mentions.md",
        "guides/editing.md",
        "guides/annotations-and-analysis.md",
        "guides/persistence.md",
        "guides/adapters.md",
        "guides/research.md",
        {"examples/README.md", filename: "examples", title: "Live Examples"}
      ],
      groups_for_extras: [
        Overview: ~r/(README|CHANGELOG|LICENSE)/,
        "Design & Architecture": ~r/guides\/(architecture|lossless-fountain|ir|cast-and-mentions|editing)/,
        "Capabilities & Runtime": ~r/guides\/(annotations-and-analysis|persistence|adapters)/,
        "Research & Precedents": ~r/guides\/research/,
        "Live Examples": ~r/examples/
      ],
      groups_for_modules: [
        "Core & Document": [
          Fount,
          Fount.Document,
          Fount.Screenplay,
          Fount.Writer,
          Fount.Cast.Character,
          Fount.Cast.Mention,
          Fount.Query,
          Fount.Validate,
          Fount.Diff,
          Fount.Builder,
          Fount.Fragment,
          Fount.Report,
          Fount.SceneHeading,
          Fount.Identity,
          Fount.Index,
          Fount.Revision,
          Fount.Diagnostic,
          Fount.Id
        ],
        "Fountain & Source CST": [
          Fount.Source,
          Fount.Source.Line,
          Fount.Source.Span,
          Fount.Fountain.Classifier,
          Fount.Fountain.CST,
          Fount.Fountain.Inline,
          Fount.Fountain.Parser,
          Fount.Fountain.Scanner,
          Fount.Fountain.Serializer
        ],
        "Screenplay IR": [
          Fount.IR,
          Fount.IR.Script,
          Fount.IR.Scene,
          Fount.IR.Element,
          Fount.IR.DialogueBlock,
          Fount.IR.OutlineNode,
          Fount.IR.TitlePage
        ],
        "Edit Algebra": [
          Fount.Edit,
          Fount.Edit.ChangeSet,
          Fount.Edit.Op,
          Fount.Edit.Patch,
          Fount.Edit.Step
        ],
        "Annotations & Analyzers": [
          Fount.Annotation,
          Fount.Annotations,
          Fount.Annotation.Provenance,
          Fount.Annotation.Target,
          Fount.Analyzer,
          Fount.Analyzers.Characters,
          Fount.Analyzers.CharacterEntities,
          Fount.Analyzers.Dialogue,
          Fount.Analyzers.Locations
        ],
        "Semantic Story World": [
          Fount.Semantics.Entity,
          Fount.Semantics.Event,
          Fount.Semantics.Graph,
          Fount.Semantics.Mention,
          Fount.Semantics.Relation
        ],
        Adapters: [
          Fount.Adapter,
          Fount.Adapter.FDX,
          Fount.Adapter.JSON
        ],
        Persistence: [
          Fount.Repo,
          Fount.Persistence,
          Fount.Persistence.Query
        ]
      ]
    ]
  end

  defp package do
    [
      name: "fount",
      maintainers: ["nshkrdotcom"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib priv guides assets examples mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end
end
