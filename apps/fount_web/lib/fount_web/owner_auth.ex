defmodule FountWeb.OwnerAuth do
  @moduledoc "Local one-owner authentication. Identity is derived from the signed server session only."
  import Plug.Conn

  def init(action), do: action

  def call(conn, :fetch_owner), do: fetch_owner(conn, [])
  def call(conn, :require_owner), do: require_owner(conn, [])

  def fetch_owner(conn, _opts) do
    owner = owner_config()

    if get_session(conn, :owner_id) == owner.id,
      do: assign(conn, :current_owner, owner.id),
      else: assign(conn, :current_owner, nil)
  end

  def require_owner(%Plug.Conn{assigns: %{current_owner: owner}} = conn, _opts) when is_binary(owner), do: conn

  def require_owner(conn, _opts) do
    conn |> Phoenix.Controller.put_flash(:error, "Sign in to the local Fount owner session.") |> Phoenix.Controller.redirect(to: "/login") |> halt()
  end

  def log_in(conn, token) when is_binary(token) do
    owner = owner_config()

    if secure_equal?(token, owner.token) do
      conn |> configure_session(renew: true) |> put_session(:owner_id, owner.id) |> {:ok, owner.id}
    else
      {:error, :invalid_credentials}
    end
  end

  def log_in(_conn, _token), do: {:error, :invalid_credentials}

  def log_out(conn), do: configure_session(conn, drop: true)

  def on_mount(:ensure_authenticated, _params, session, socket) do
    owner = owner_config()

    if session["owner_id"] == owner.id do
      {:cont, Phoenix.Component.assign(socket, :current_owner, owner.id)}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: "/login")}
    end
  end

  def owner_id, do: owner_config().id

  defp owner_config do
    config = Application.fetch_env!(:fount_web, :owner)
    %{id: Keyword.fetch!(config, :id), token: Keyword.fetch!(config, :token)}
  end

  defp secure_equal?(left, right) when byte_size(left) == byte_size(right), do: Plug.Crypto.secure_compare(left, right)
  defp secure_equal?(_, _), do: false
end
