defmodule FountWeb.SessionController do
  use FountWeb, :controller

  def new(conn, _params), do: render(conn, :new, error: nil)

  def create(conn, %{"session" => %{"token" => token}}) do
    case FountWeb.OwnerAuth.log_in(conn, token) do
      {:ok, authenticated_conn, _owner} ->
        authenticated_conn
        |> put_flash(:info, "Owner session authenticated.")
        |> redirect(to: "/")

      {:error, _} ->
        conn |> put_status(:unauthorized) |> render(:new, error: "Invalid owner token")
    end
  end

  def create(conn, _params),
    do: conn |> put_status(:bad_request) |> render(:new, error: "Owner token is required")

  def delete(conn, _params), do: conn |> FountWeb.OwnerAuth.log_out() |> redirect(to: "/login")
end
