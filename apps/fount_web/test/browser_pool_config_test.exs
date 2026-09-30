defmodule FountWeb.BrowserPoolConfigTest do
  use ExUnit.Case, async: false

  test "browser server uses pooled connections while ExUnit keeps Sandbox" do
    previous = System.get_env("PHX_SERVER")

    on_exit(fn ->
      if previous,
        do: System.put_env("PHX_SERVER", previous),
        else: System.delete_env("PHX_SERVER")
    end)

    path = Path.expand("../config/test.exs", __DIR__)
    System.put_env("PHX_SERVER", "true")
    config = Config.Reader.read!(path, env: :test)
    assert config[:fount][Fount.Repo][:pool] == DBConnection.ConnectionPool

    System.delete_env("PHX_SERVER")
    config = Config.Reader.read!(path, env: :test)
    assert config[:fount][Fount.Repo][:pool] == Ecto.Adapters.SQL.Sandbox
  end
end
