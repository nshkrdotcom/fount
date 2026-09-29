import Config

config :fount, Fount.Repo,
  url: System.get_env("FOUNT_DATABASE_URL", "ecto://postgres:postgres@localhost/fount_test"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :fount_web, FountWeb.Endpoint,
  url: [host: "127.0.0.1", port: String.to_integer(System.get_env("PORT", "4010"))],
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT", "4010"))],
  secret_key_base: String.duplicate("t", 64),
  server: System.get_env("PHX_SERVER") == "true"

config :fount_web, :owner, id: "test-owner", token: "test-owner-token"
config :logger, level: :warning
