import Config

config :fount, ecto_repos: [Fount.Repo]

if url = System.get_env("FOUNT_DATABASE_URL") do
  config :fount, Fount.Repo, url: url, pool_size: 10
end
