if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

defmodule Fount.Workspace.MixProject do
  use Mix.Project

  def project do
    [
      app: :fount_workspace,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: [],
      deps: [workspace_dep({:blitz, "~> 0.4.1", runtime: false})],
      aliases: aliases(),
      blitz_workspace: blitz_workspace()
    ]
  end

  def cli do
    [preferred_envs: [setup: :dev, ci: :dev, test: :test]]
  end

  def blitz_env(context) do
    env = [{"MIX_ENV", context.task_config.mix_env}]

    if context.task == :test do
      {variable, default} =
        case context.project_path do
          "packages/fount" -> {"FOUNT_TEST_DATABASE", "fount_test"}
          "packages/fount_workshop" -> {"FOUNT_WORKSHOP_TEST_DATABASE", "fount_workshop_test"}
        end

      [{"FOUNT_TEST_DATABASE", System.get_env(variable, default)} | env]
    else
      env
    end
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end

  defp aliases do
    [
      setup: [
        "deps.get",
        "blitz.workspace deps_get",
        "cmd --cd packages/fount_workshop npm ci"
      ],
      test: ["blitz.workspace test"],
      ci: [
        "setup",
        "format --check-formatted",
        "deps.unlock --check-unused",
        "blitz.workspace format --check-formatted",
        "blitz.workspace lock_check",
        "blitz.workspace compile",
        "blitz.workspace test",
        "blitz.workspace credo --strict",
        "blitz.workspace dialyzer",
        "blitz.workspace docs"
      ]
    ]
  end

  defp blitz_workspace do
    [
      root: __DIR__,
      projects: ["packages/fount", "packages/fount_workshop"],
      isolation: [deps_path: true, build_path: true, lockfile: true, hex_home: "_build/hex"],
      parallelism: [
        multiplier: :auto,
        base: [
          deps_get: 4,
          format: 8,
          lock_check: 8,
          compile: 4,
          test: 4,
          credo: 4,
          dialyzer: 2,
          docs: 2
        ]
      ],
      tasks:
        Enum.map(
          [
            deps_get: [args: ["deps.get"], preflight?: false],
            format: [args: ["format"]],
            lock_check: [args: ["deps.unlock", "--check-unused"]],
            compile: [args: ["compile", "--warnings-as-errors"]],
            test: [args: ["test"], mix_env: "test", color: true],
            credo: [args: ["credo"]],
            dialyzer: [args: ["dialyzer"]],
            docs: [args: ["docs", "--warnings-as-errors"]]
          ],
          fn {task, config} ->
            {task, Keyword.merge([mix_env: "dev", env: {__MODULE__, :blitz_env}], config)}
          end
        )
    ]
  end
end
