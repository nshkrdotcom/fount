defmodule Fount.Observe.MixProject do
  use Mix.Project
  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/fount"

  def project do
    [
      app: :fount_observe,
      version: @version,
      name: "Fount.Observe",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      description:
        "Source-grounded screenplay measurements with neutral contracts, deterministic fixtures, and explicit resource limits",
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
      system_one_dependency(),
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  # The attached API snapshot is 0.6.0. A path override lets QC inspect the same
  # source without assuming that release is already available from Hex.
  defp system_one_dependency do
    case if(System.get_env("FOUNT_PACKAGE_BUILD") == "1",
           do: nil,
           else: System.get_env("FOUNT_SYSTEM_ONE_SDK_PATH")
         ) do
      nil -> {:system_one_sdk, "~> 0.6.0"}
      "" -> raise "FOUNT_SYSTEM_ONE_SDK_PATH must not be blank"
      path -> {:system_one_sdk, "~> 0.6.0", path: Path.expand(path)}
    end
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
      canonical: "https://hexdocs.pm/fount_observe",
      logo: "assets/fount_observe.svg",
      assets: %{"assets" => "assets"},
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "guides/architecture.md",
        "guides/usage.md",
        "guides/measurement-substrate.md",
        "guides/verification.md",
        {"examples/README.md", filename: "examples"}
      ],
      groups_for_extras: [
        Overview: ~r/(README|CHANGELOG|LICENSE)/,
        Guides: ~r/guides\//,
        Examples: ~r/examples\//
      ],
      groups_for_modules: [
        Contracts: [
          Fount.Observe.Question,
          Fount.Observe.OutputContract,
          Fount.Observe.Request,
          Fount.Observe.MeasurementResult,
          Fount.Observe.Observation,
          Fount.Observe.Distribution,
          Fount.Observe.EvidenceRef,
          Fount.Observe.TargetRef,
          Fount.Observe.Context,
          Fount.Observe.Error
        ],
        Execution: [
          Fount.Observe,
          Fount.Observe.Executor,
          Fount.Observe.SceneQuestion,
          Fount.Observe.Recording,
          Fount.Observe.Resources,
          Fount.Observe.Budget,
          Fount.Observe.Cancellation
        ],
        Providers: [
          Fount.Observe.Provider,
          Fount.Observe.Sandbox,
          Fount.Observe.Providers.SystemOne
        ],
        Assets: [
          Fount.Observe.Lens,
          Fount.Observe.Registry,
          Fount.Observe.Projection,
          Fount.Observe.Calibration
        ],
        Cache: [Fount.Observe.Cache, Fount.Observe.Cache.Memory, Fount.Observe.Cache.ETS]
      ]
    ]
  end

  defp package do
    [
      name: "fount_observe",
      maintainers: ["nshkrdotcom"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv guides assets examples mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end
end
