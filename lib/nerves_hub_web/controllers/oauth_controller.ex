defmodule NervesHubWeb.OAuthController do
  use NervesHubWeb, :controller

  alias NervesHub.Accounts
  alias NervesHubWeb.Auth

  plug(Ueberauth)

  # Ueberauth answers the request phase itself for a provider it is configured
  # with, redirecting to the provider and halting. Reaching an action means the
  # path named a provider it doesn't know (`/auth/login`, `/auth/.env`), so
  # there is nothing here.
  def request(conn, _params), do: not_found(conn)

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    render(conn, :auth_failure)
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case Accounts.update_or_create_user_from_ueberauth(auth) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Welcome back!")
        |> Auth.log_in_user(user)

      {:error, _reason} ->
        render(conn, :auth_failure)
    end
  end

  def callback(conn, _params), do: not_found(conn)

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(html: NervesHubWeb.ErrorHTML)
    |> render("404.html")
  end
end
