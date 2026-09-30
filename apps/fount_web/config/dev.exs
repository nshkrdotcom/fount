import Config

config :fount, Fount.Repo,
  url: "ecto://postgres:postgres@localhost/fount_dev",
  pool_size: 10,
  log: false,
  show_sensitive_data_on_connection_error: true,
  stacktrace: true

config :fount_web, FountWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: String.duplicate("d", 64),
  watchers: [esbuild: {Esbuild, :install_and_run, [:fount_web, ~w(--sourcemap=inline --watch)]}]

config :fount_web, dev_routes: true
