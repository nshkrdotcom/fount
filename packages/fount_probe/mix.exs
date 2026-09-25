defmodule FountProbe.MixProject do
  use Mix.Project

  def project do
    [
      app: :fount_probe,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]

  defp deps do
    [
      {:fount, path: "../fount"},
      {:system_one_sdk, path: "../../../system_one_sdk/packages/system_one_sdk"},
      {:inference, "~> 0.4.0"},
      {:agent_session_manager, "~> 0.16.0"},
      {:jason, "~> 1.4"}
    ]
  end
end
