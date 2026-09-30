defmodule FountWeb.BrowserPoolConfigTest do
  use ExUnit.Case, async: false

  test "browser server uses pooled connections while ExUnit keeps Sandbox" do
    previous = System.get_env("PHX_SERVER")

    on_exit(fn ->
      if previous,
        do: System.put_env("PHX_SERVER", previous),
        else: System.delete_env("PHX_SERVER")
    end)

    path = Path.expand("../config/runtime.exs", __DIR__)
    System.put_env("PHX_SERVER", "true")
    config = Config.Reader.read!(path, env: :test)
    assert config[:fount][Fount.Repo][:pool] == DBConnection.ConnectionPool

    System.delete_env("PHX_SERVER")
    config = Config.Reader.read!(path, env: :test)
    assert config[:fount][Fount.Repo][:pool] == Ecto.Adapters.SQL.Sandbox
  end

  test "runtime config applies development database and port overrides" do
    previous =
      for key <- ["FOUNT_DATABASE_URL", "PORT"], into: %{}, do: {key, System.get_env(key)}

    on_exit(fn ->
      for {key, value} <- previous do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    System.put_env("FOUNT_DATABASE_URL", "ecto://localhost/fount_runtime_config_probe")
    System.put_env("PORT", "4057")
    config = Config.Reader.read!(Path.expand("../config/runtime.exs", __DIR__), env: :dev)
    assert config[:fount][Fount.Repo][:url] == "ecto://localhost/fount_runtime_config_probe"
    assert config[:fount_web][FountWeb.Endpoint][:http][:port] == 4057
  end
end
