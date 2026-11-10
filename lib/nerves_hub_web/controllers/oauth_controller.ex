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

      # The email is on an account no Google account is linked to. Signing in
      # with that account's password, or resetting it, links them, see
      # `NervesHubWeb.Auth.link_pending_google_account/2`.
      {:error, :link_required} ->
        conn
        |> put_session(:pending_google_link, Accounts.pending_google_link(auth))
        |> put_flash(
          :info,
          "An account with #{auth.info.email} already exists. Sign in with its password to connect your Google account to it, or reset the password if you don't know it."
        )
        |> redirect(to: ~p"/login")

      {:error, :google_account_mismatch} ->
        login_error(conn, "The account with #{auth.info.email} is connected to a different Google account.")

      {:error, :email_not_verified} ->
        login_error(conn, "Google hasn't verified #{auth.info.email}, so it can't be used to sign in.")

      {:error, :sign_up_closed} ->
        login_error(
          conn,
          "There's no account for #{auth.info.email}. Please contact your platform admin for an invite."
        )

      {:error, _reason} ->
        render(conn, :auth_failure)
    end
  end

  def callback(conn, _params), do: not_found(conn)

  defp login_error(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/login")
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(html: NervesHubWeb.ErrorHTML)
    |> render("404.html")
  end
end
