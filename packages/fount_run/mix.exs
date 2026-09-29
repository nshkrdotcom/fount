defmodule FountRun.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/fount"

  def project do
    [
      app: :fount_run,
      version: @version,
      name: "FountRun",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description: "Durable, policy-aware run orchestration foundation for Fount",
      source_url: @source_url,
      homepage_url: @source_url,
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix]],
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto], mod: {FountRun.Application, []}]
  end

  defp deps do
    [
      workspace_dep(:fount, "~> 0.1.0", "../fount"),
      workspace_dep(:fount_workshop, "~> 0.1.0", "../fount_workshop"),
      {:jason, "~> 1.4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.20"},
      {:telemetry, "~> 1.0"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
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
      name: "FountRun",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      canonical: "https://hexdocs.pm/fount_run",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "guides/architecture.md",
        "guides/storage.md"
      ]
    ]
  end

  defp package do
    [
      name: "fount_run",
      maintainers: ["nshkrdotcom"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv guides mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end
end
