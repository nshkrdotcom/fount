import Config

config :fount, ecto_repos: [Fount.Repo]

config :fount_web, FountWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: FountWeb.ErrorHTML, json: FountWeb.ErrorJSON], layout: false],
  pubsub_server: FountWeb.PubSub,
  live_view: [signing_salt: "fount-phase06"]

config :fount_web, :owner,
  id: "local-owner",
  token: "fount-demo-owner-token"

config :fount_web, :demo,
  enabled: true,
  service_approver_id: "demo-service",
  agent_approver_id: "demo-agent"

config :fount_web, :observe, mode: :sandbox

config :fount_web, :semantic_assessment, mode: :disabled

config :fount_web, :authoring,
  autosave_ms: 60_000,
  history_limit: 30,
  draft_limit: 12,
  max_source_bytes: 1_048_576

config :fount_web, :artifact_root, Path.expand("../../_artifacts/fount_web", __DIR__)

config :esbuild,
  version: "0.25.10",
  fount_web: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :phoenix, :json_library, Jason
config :mime, :types, %{"text/plain" => ["fountain"], "application/xml" => ["fdx"]}

import_config "#{config_env()}.exs"
