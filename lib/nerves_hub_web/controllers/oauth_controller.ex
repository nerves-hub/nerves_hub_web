defmodule NervesHubWeb.OAuthController do
  use NervesHubWeb, :controller

  alias NervesHub.Accounts
  alias NervesHub.Accounts.User
  alias NervesHubWeb.Auth

  # How long after leaving the account page Google has to send someone back.
  @google_intent_seconds 10 * 60

  plug(:fetch_google_intent)
  plug(Ueberauth)

  # Ueberauth answers the request phase itself for a provider it is configured
  # with, redirecting to the provider and halting. Reaching an action means the
  # path named a provider it doesn't know (`/auth/login`, `/auth/.env`), so
  # there is nothing here.
  def request(conn, _params), do: not_found(conn)

  # A signed in user back from Google, where their account page sent them.
  def callback(%{assigns: %{google_intent: %{} = intent}} = conn, _params) do
    conn
    |> delete_session(:google_intent)
    |> finish_google_intent(intent, conn.assigns.current_scope.user, conn.assigns[:ueberauth_auth])
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    render(conn, :auth_failure)
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case Accounts.update_or_create_user_from_ueberauth(auth) do
      {:ok, user} ->
        Auth.sign_in(conn, user, %{}, flash: "Welcome back!")

      # The email is on an account no Google account is linked to. Signing in
      # with that account's password, or resetting it, links them, see
      # `NervesHubWeb.Auth.sign_in/4`'s `:link_google`.
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

  # Signing in with Google is for someone signed out. A signed in user only
  # comes here from their account page (`NervesHubWeb.ConfirmIdentityController.google/2`),
  # which leaves what they came for in the session; anyone else signed in is
  # sent on.
  defp fetch_google_intent(conn, _opts) do
    case {conn.assigns[:current_scope], get_session(conn, :google_intent)} do
      {%{user: %User{id: user_id}}, %{"user_id" => user_id, "started_at" => started_at} = intent}
      when is_integer(started_at) ->
        if System.os_time(:second) - started_at <= @google_intent_seconds do
          assign(conn, :google_intent, intent)
        else
          conn
          |> delete_session(:google_intent)
          |> Auth.redirect_if_user_is_authenticated([])
        end

      _ ->
        Auth.redirect_if_user_is_authenticated(conn, [])
    end
  end

  defp finish_google_intent(conn, %{"return_to" => return_to}, _user, nil) do
    conn
    |> put_flash(:error, "Google didn't confirm your account. Try again.")
    |> redirect(to: Auth.account_return_to(return_to))
  end

  defp finish_google_intent(conn, %{"action" => "confirm", "return_to" => return_to}, user, auth) do
    return_to = Auth.account_return_to(return_to)

    if is_binary(user.google_id) and auth.uid == user.google_id do
      conn
      |> Auth.mark_authenticated()
      |> redirect(to: return_to)
    else
      conn
      |> put_flash(:error, "That isn't the Google account connected to yours. Try again and choose that one.")
      |> redirect(to: ~p"/account/confirm?#{[return_to: return_to]}")
    end
  end

  defp finish_google_intent(conn, %{"action" => "connect", "return_to" => return_to}, user, auth) do
    return_to = Auth.account_return_to(return_to)

    case Accounts.connect_google_account(user, auth) do
      {:ok, _user} ->
        conn
        # Signing in to Google just now proves it's them as well as the
        # password does.
        |> Auth.mark_authenticated()
        |> put_flash(:info, "Your Google account is now connected. You can sign in with it.")
        |> redirect(to: return_to)

      {:error, reason} ->
        conn
        |> put_flash(:error, connect_error(reason, user, auth))
        |> redirect(to: return_to)
    end
  end

  defp connect_error(:email_mismatch, user, auth),
    do: "That Google account is #{auth.info.email}. Connect the one for #{user.email}."

  defp connect_error(:email_not_verified, _user, auth),
    do: "Google hasn't verified #{auth.info.email}, so it can't be connected."

  defp connect_error(:unconfirmed, _user, _auth), do: "Confirm your email address first, then connect Google."
  defp connect_error(:already_linked, _user, _auth), do: "Your account is already connected to a Google account."

  defp connect_error(%Ecto.Changeset{}, _user, _auth), do: "That Google account is connected to another account."

  defp connect_error(_reason, _user, _auth), do: "Google couldn't be connected. Try again."

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
