defmodule NervesHubWeb.ConfirmIdentityController do
  @moduledoc """
  The "Confirm it's you" page, where a signed in user proves who they are
  again before a change that needs a recent sign-in.

  It takes the password or Google, whichever the account has, so an account
  without a password is never asked for one (see
  `NervesHubWeb.Auth.recently_authenticated?/1`). The account page also starts
  connecting a Google account here, which goes out to Google the same way.
  """
  use NervesHubWeb, :controller

  alias NervesHub.Accounts
  alias NervesHub.Accounts.User
  alias NervesHubWeb.Auth
  alias NervesHubWeb.Plugs.Attack

  def new(conn, params) do
    render_new(conn, Auth.account_return_to(params["return_to"]))
  end

  def create(conn, params) do
    user = conn.assigns.current_scope.user
    return_to = Auth.account_return_to(params["return_to"])

    with {:allow, _data} <- Attack.confirm_identity_throttle(user.id),
         true <- User.valid_password?(user, params["password"] || "") do
      conn
      |> Auth.mark_authenticated()
      |> redirect(to: return_to)
    else
      {:block, _data} ->
        conn
        |> put_status(:too_many_requests)
        |> render_new(return_to, "Too many tries. To keep your account safe, wait ten minutes, then try again.")

      false ->
        render_new(conn, return_to, "That password isn't right.")
    end
  end

  @doc """
  Sends the user to Google, to confirm it's them (`"intent" => "confirm"`) or
  to connect a Google account to theirs (`"connect"`).
  `NervesHubWeb.OAuthController` finishes either when Google sends them back.
  """
  def google(conn, params) do
    user = conn.assigns.current_scope.user
    return_to = Auth.account_return_to(params["return_to"])

    case google_intent(user, params["intent"], Auth.recently_authenticated?(conn)) do
      {:ok, intent} ->
        conn
        |> put_session(:google_intent, %{
          "action" => intent,
          "user_id" => user.id,
          "return_to" => return_to,
          "started_at" => System.os_time(:second)
        })
        |> redirect(to: ~p"/auth/google?#{[prompt: "select_account", login_hint: user.email]}")

      # Connecting adds a way into the account, so it needs a recent sign-in
      # like removing one does.
      :confirm_first ->
        redirect(conn, to: ~p"/account/confirm?#{[return_to: return_to]}")

      :error ->
        conn
        |> put_flash(:error, "Google sign-in isn't available for your account.")
        |> redirect(to: return_to)
    end
  end

  defp google_intent(user, intent, recent?) do
    if Accounts.google_sign_in_enabled?(), do: google_intent_for(user, intent, recent?), else: :error
  end

  defp google_intent_for(%User{google_id: google_id}, "confirm", _recent?) when is_binary(google_id),
    do: {:ok, "confirm"}

  defp google_intent_for(%User{google_id: nil}, "connect", true), do: {:ok, "connect"}
  defp google_intent_for(%User{google_id: nil}, "connect", false), do: :confirm_first
  defp google_intent_for(_user, _intent, _recent?), do: :error

  defp render_new(conn, return_to, error \\ nil) do
    render(conn, :new,
      page_title: "Confirm it's you",
      return_to: return_to,
      methods: Accounts.sign_in_methods(conn.assigns.current_scope.user),
      error: error
    )
  end
end
