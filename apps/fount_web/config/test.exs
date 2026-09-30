import Config

config :fount, Fount.Repo,
  url: "ecto://postgres:postgres@localhost/fount_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :fount_web, FountWeb.Endpoint,
  url: [host: "127.0.0.1", port: 4010],
  http: [ip: {127, 0, 0, 1}, port: 4010],
  secret_key_base: String.duplicate("t", 64),
  server: false

config :fount_web, :owner, id: "test-owner", token: "test-owner-token"
config :logger, level: :warning
