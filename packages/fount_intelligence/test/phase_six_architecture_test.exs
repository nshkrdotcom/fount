defmodule Fount.Intelligence.PhaseSixArchitectureTest do
  use ExUnit.Case, async: true

  test "pure Phase-6 capability modules do not acquire, persist, generate, or read runtime state" do
    root = Path.expand("../lib/fount/intelligence/capabilities", __DIR__)

    sources =
      root
      |> Path.join("*.ex")
      |> Path.wildcard()
      |> Enum.reject(fn path ->
        String.ends_with?(path, "/interpretation.ex") or
          String.ends_with?(path, "/decision_policy.ex")
      end)
      |> Enum.map_join("\n", &File.read!/1)

    for forbidden <- [
          "SystemOneSDK",
          "Inference.",
          "ASM.",
          "Fount.Repo",
          "Fount.Persistence",
          "Fount.Intelligence.Acquisition",
          "Fount.Intelligence.Playbooks",
          "System.get_env",
          "DateTime.utc_now",
          "Fount.ID.v4"
        ] do
      refute String.contains?(sources, forbidden)
    end
  end
end
