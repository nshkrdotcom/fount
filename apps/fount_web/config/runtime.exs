import Config

if config_env() == :prod do
  database_url = System.fetch_env!("FOUNT_DATABASE_URL")
  secret_key_base = System.fetch_env!("SECRET_KEY_BASE")
  host = System.get_env("PHX_HOST", "localhost")
  port = String.to_integer(System.get_env("PORT", "4000"))
  owner_id = System.fetch_env!("FOUNT_OWNER_ID")
  owner_token = System.fetch_env!("FOUNT_OWNER_TOKEN")
  artifact_root = System.fetch_env!("FOUNT_ARTIFACT_ROOT")

  config :fount, Fount.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

  config :fount_web, FountWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true

  config :fount_web, :owner, id: owner_id, token: owner_token
  config :fount_web, :artifact_root, artifact_root
  config :fount_run, :artifact_root, artifact_root
else
  owner = Application.fetch_env!(:fount_web, :owner)

  artifact_root =
    System.get_env("FOUNT_ARTIFACT_ROOT", Application.fetch_env!(:fount_web, :artifact_root))

  config :fount_web, :owner,
    id: System.get_env("FOUNT_OWNER_ID", Keyword.fetch!(owner, :id)),
    token: System.get_env("FOUNT_OWNER_TOKEN", Keyword.fetch!(owner, :token))

  config :fount_web, :artifact_root, artifact_root
  config :fount_run, :artifact_root, artifact_root
end
