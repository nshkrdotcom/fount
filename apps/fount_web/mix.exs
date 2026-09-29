defmodule FountWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :fount_web,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [mod: {FountWeb.Application, []}, extra_applications: [:logger, :runtime_tools]]
  end

  def cli do
    [preferred_envs: ["fount_web.migrate": :dev, "fount_web.browser": :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:fount, path: "../../packages/fount"},
      {:fount_run, path: "../../packages/fount_run"},
      {:inference, "~> 0.5.0"},
      {:phoenix, "~> 1.8.1"},
      {:phoenix_live_view, "~> 1.2"},
      {:phoenix_ecto, "~> 4.6"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:bandit, "~> 1.12"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.20"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:jason, "~> 1.4.5"},
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_poller, "~> 1.3"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": ["esbuild fount_web"],
      "assets.deploy": ["esbuild fount_web --minify", "phx.digest"]
    ]
  end
end
