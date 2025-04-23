defmodule NervesHubWeb.OAuthController do
  use NervesHubWeb, :controller

  alias NervesHub.Accounts
  alias NervesHubWeb.Auth

  plug(Ueberauth)

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
end
