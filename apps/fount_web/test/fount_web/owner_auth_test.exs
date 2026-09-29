defmodule FountWeb.OwnerAuthTest do
  use FountWeb.ConnCase, async: true

  test "unauthenticated owner surfaces redirect to login", %{conn: conn} do
    conn = get(conn, "/")
    assert redirected_to(conn) == "/login"
  end

  test "invalid token does not create an owner session", %{conn: conn} do
    conn = post(conn, "/login", %{"session" => %{"token" => "wrong"}})
    assert conn.status == 401
  end

  test "valid token establishes only the configured owner id", %{conn: conn} do
    conn = FountWeb.ConnCase.login(conn)
    assert redirected_to(conn) == "/"
    assert Plug.Conn.get_session(conn, :owner_id) == "test-owner"
  end
end
