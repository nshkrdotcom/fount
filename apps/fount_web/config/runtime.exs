import Config

required_nonblank = fn name ->
  case System.get_env(name) do
    nil ->
      raise "#{name} is required for the configured Fount Observe provider"

    value ->
      case String.trim(value) do
        "" -> raise "#{name} must be nonblank for the configured Fount Observe provider"
        trimmed -> trimmed
      end
  end
end

optional_nonblank = fn name ->
  case System.get_env(name) do
    nil ->
      nil

    value ->
      case String.trim(value) do
        "" -> raise "#{name} is set but blank; unset it or provide a nonblank value"
        trimmed -> trimmed
      end
  end
end

validate_base_url = fn value, name ->
  uri = URI.parse(value)

  cond do
    uri.scheme not in ["http", "https"] ->
      raise "#{name} must use http or https"

    is_nil(uri.host) or uri.host == "" ->
      raise "#{name} must include a host"

    not is_nil(uri.userinfo) ->
      raise "#{name} must not contain URL credentials"

    not is_nil(uri.query) ->
      raise "#{name} must not contain a query string"

    not is_nil(uri.fragment) ->
      raise "#{name} must not contain a fragment"

    true ->
      String.trim_trailing(value, "/")
  end
end

observe_mode =
  System.get_env(
    "FOUNT_OBSERVE_MODE",
    if(config_env() == :prod, do: "system_one", else: "sandbox")
  )
  |> String.trim()

runtime_env = config_env()

observe_config =
  case observe_mode do
    "sandbox" when runtime_env != :prod ->
      [mode: :sandbox]

    "sandbox" ->
      raise "FOUNT_OBSERVE_MODE=sandbox is deterministic test/demo mode and is not allowed in production"

    "compatibility" ->
      [mode: :compatibility]

    "system_one" ->
      endpoint_kind =
        case System.get_env("FOUNT_SYSTEM_ONE_ENDPOINT_KIND", "typesafe") |> String.trim() do
          "typesafe" -> :typesafe
          "endpoint" -> :endpoint
          _ -> raise "FOUNT_SYSTEM_ONE_ENDPOINT_KIND must be typesafe or endpoint"
        end

      model = required_nonblank.("SYSTEM_ONE_MODEL")

      provider_opts =
        case endpoint_kind do
          :typesafe ->
            api_key = required_nonblank.("SYSTEM_ONE_API_KEY")
            base_url = optional_nonblank.("SYSTEM_ONE_BASE_URL")

            [endpoint_kind: :typesafe, api_key: api_key, model: model]
            |> then(fn opts ->
              if base_url,
                do:
                  Keyword.put(
                    opts,
                    :base_url,
                    validate_base_url.(base_url, "SYSTEM_ONE_BASE_URL")
                  ),
                else: opts
            end)

          :endpoint ->
            base_url =
              required_nonblank.("SYSTEM_ONE_BASE_URL")
              |> then(&validate_base_url.(&1, "SYSTEM_ONE_BASE_URL"))

            api_key = optional_nonblank.("SYSTEM_ONE_API_KEY")

            [endpoint_kind: :endpoint, base_url: base_url, model: model]
            |> then(fn opts ->
              if api_key, do: Keyword.put(opts, :api_key, api_key), else: opts
            end)
        end

      [mode: :system_one, provider_opts: provider_opts]

    _ ->
      raise "FOUNT_OBSERVE_MODE must be system_one, compatibility, or sandbox outside production"
  end

config :fount_web, :observe, observe_config

semantic_assessment_mode =
  System.get_env("FOUNT_SEMANTIC_ASSESSMENT_MODE", "disabled")
  |> String.trim()

semantic_assessment_config =
  case semantic_assessment_mode do
    "disabled" ->
      [mode: :disabled]

    "codex" ->
      cli_path = optional_nonblank.("CODEX_PATH") || "codex"
      auth_asserted = System.get_env("FOUNT_CODEX_AUTH_ASSERTED", "false") |> String.trim() |> String.downcase() == "true"
      [mode: :codex, cli_path: cli_path, auth_asserted: auth_asserted]

    "deterministic_fixture" when config_env() == :test ->
      [
        mode: :deterministic_fixture,
        client_factory: {FountWeb.SemanticFixtureAdapter, :client, []}
      ]

    other ->
      raise "FOUNT_SEMANTIC_ASSESSMENT_MODE must be disabled or codex (or deterministic_fixture in test), got #{inspect(other)}"
  end

config :fount_web, :semantic_assessment, semantic_assessment_config

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
  repo = Application.fetch_env!(:fount, Fount.Repo)
  endpoint = Application.fetch_env!(:fount_web, FountWeb.Endpoint)
  port = System.get_env("PORT", to_string(endpoint[:http][:port])) |> String.to_integer()

  config :fount, Fount.Repo, url: System.get_env("FOUNT_DATABASE_URL", Keyword.fetch!(repo, :url))

  config :fount_web, FountWeb.Endpoint,
    http: [port: port],
    url: [port: port]

  if config_env() == :test do
    browser_server? = System.get_env("PHX_SERVER") == "true"

    config :fount, Fount.Repo,
      pool: if(browser_server?, do: DBConnection.ConnectionPool, else: Ecto.Adapters.SQL.Sandbox)

    config :fount_web, FountWeb.Endpoint, server: browser_server?
  end

  owner = Application.fetch_env!(:fount_web, :owner)

  artifact_root =
    System.get_env("FOUNT_ARTIFACT_ROOT", Application.fetch_env!(:fount_web, :artifact_root))

  config :fount_web, :owner,
    id: System.get_env("FOUNT_OWNER_ID", Keyword.fetch!(owner, :id)),
    token: System.get_env("FOUNT_OWNER_TOKEN", Keyword.fetch!(owner, :token))

  config :fount_web, :artifact_root, artifact_root
  config :fount_run, :artifact_root, artifact_root
end
