defmodule FountWorkshop.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/fount"

  def project do
    [
      app: :fount_workshop,
      version: @version,
      name: "FountWorkshop",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      description:
        "Writer revision workshop, agent loop, and PDF export for the Fount screenplay framework",
      source_url: @source_url,
      homepage_url: @source_url,
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix]],
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      workspace_dep(:fount_intelligence, "~> 0.1.0", "../fount_intelligence"),
      workspace_dep(:fount, "~> 0.1.0", "../fount"),
      {:inference, "~> 0.5.0"},
      {:agent_session_manager, "~> 0.17.1"},
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
        "LICENSE",
        "guides/architecture.md",
        "guides/creative-workflows.md",
        "guides/discovery-and-scene-exploration.md",
        "guides/cinematic-revision-rehearsal-and-voice.md",
        "guides/research-notes-and-consequences.md",
        "guides/intelligence-integration.md",
        "guides/scene-revision-loop.md",
        "guides/proposals-and-diffs.md",
        "guides/pdf-export-and-inspection.md",
        "guides/submission-checks.md",
        "guides/table-reads-and-audio.md",
        "guides/read-share-resume-and-usefulness.md",
        {"examples/phase_twelve/README.md",
         filename: "phase-twelve-example", title: "Phase 12 Example"},
        {"examples/phase_thirteen/README.md",
         filename: "phase-thirteen-example", title: "Phase 13 Example"},
        {"examples/phase_fourteen/README.md",
         filename: "phase-fourteen-example", title: "Phase 14 Example"},
        {"examples/phase_fifteen/README.md",
         filename: "phase-fifteen-example", title: "Phase 15 Example"},
        {"examples/README.md", filename: "examples", title: "Live Examples"}
      ],
      groups_for_extras: [
        Overview: ~r/(README|CHANGELOG|LICENSE)/,
        "Agent Workflows":
          ~r/guides\/(architecture|creative-workflows|discovery-and-scene-exploration|cinematic-revision-rehearsal-and-voice|research-notes-and-consequences|intelligence-integration|scene-revision-loop|proposals-and-diffs)/,
        "Export & Inspection": ~r/guides\/(pdf-export-and-inspection|submission-checks)/,
        "Rehearsal & Audio": ~r/guides\/(table-reads-and-audio|read-share-resume-and-usefulness)/,
        "Live Examples": ~r/examples/
      ],
      groups_for_modules: [
        Workshop: [
          FountWorkshop,
          FountWorkshop.Develop,
          FountWorkshop.Review,
          FountWorkshop.Rehearsal,
          FountWorkshop.Comparison,
          FountWorkshop.SequenceRebuild,
          FountWorkshop.TargetedRewrite,
          FountWorkshop.NoteResponse,
          FountWorkshop.Pass,
          FountWorkshop.CharacterRewrite,
          FountWorkshop.Recover,
          FountWorkshop.TableRead,
          FountWorkshop.Share,
          FountWorkshop.Usefulness,
          FountWorkshop.Speech.Espeak
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
      files: ~w(lib priv guides assets examples mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end
end
