defmodule FountWeb.ConnCase do
  @moduledoc "Shared authenticated connection setup for host web tests."
  use ExUnit.CaseTemplate
  alias Ecto.Adapters.SQL.Sandbox
  alias Phoenix.ConnTest
  require Phoenix.ConnTest
  @endpoint FountWeb.Endpoint

  using do
    quote do
      @endpoint FountWeb.Endpoint
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
    end
  end

  setup tags do
    pid = Sandbox.start_owner!(Fount.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    {:ok, conn: ConnTest.build_conn()}
  end

  def login(conn, token \\ "test-owner-token") do
    ConnTest.post(conn, "/login", %{"session" => %{"token" => token}})
  end
end
