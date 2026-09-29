defmodule FountWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint FountWeb.Endpoint
      use Phoenix.ConnTest
      import Phoenix.LiveViewTest
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Fount.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  def login(conn, token \\ "test-owner-token") do
    Phoenix.ConnTest.post(conn, "/login", %{"session" => %{"token" => token}})
  end
end
