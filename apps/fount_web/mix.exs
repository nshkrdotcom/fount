defmodule FountWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :fount_web,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      listeners: [Phoenix.CodeReloader],
      dialyzer: [plt_add_apps: [:mix]],
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
      {:fount_observe, path: "../../packages/fount_observe"},
      {:inference, "~> 0.5.1"},
      {:phoenix, "~> 1.8.15"},
      {:phoenix_live_view, "~> 1.2.12"},
      {:lazy_html, "~> 0.1.13", only: :test},
      {:phoenix_ecto, "~> 4.7.0"},
      {:phoenix_html, "~> 4.3.0"},
      {:phoenix_live_reload, "~> 1.7.0", only: :dev},
      {:bandit, "~> 1.12.5"},
      {:ecto_sql, "~> 3.14.0"},
      {:postgrex, "~> 0.22.4"},
      {:esbuild, "~> 0.10.0", runtime: Mix.env() == :dev},
      {:jason, "~> 1.4.5"},
      {:telemetry_metrics, "~> 1.2.0"},
      {:telemetry_poller, "~> 1.3.0"},
      {:ex_doc, "~> 0.40.4", only: :dev, runtime: false},
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.8", only: :dev, runtime: false}
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
