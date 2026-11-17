defmodule NervesHubWeb.ConfirmIdentityController do
  @moduledoc """
  The "Confirm it's you" page, where a signed in user proves who they are
  again before a change that needs a recent sign-in.

  It takes the password or Google, whichever the account has, so an account
  without a password is never asked for one (see
  `NervesHubWeb.Auth.recently_authenticated?/1`). An account with two-factor
  on also gives a code, as signing in would ask for, since a browser still
  signed in to Google confirms with one click. The account page also starts
  connecting a Google account here, which goes out to Google the same way.
  """
  use NervesHubWeb, :controller

  alias NervesHub.Accounts
  alias NervesHub.Accounts.TwoFactor
  alias NervesHub.Accounts.User
  alias NervesHubWeb.Auth
  alias NervesHubWeb.Plugs.Attack

  plug(:require_no_permission, :the_users_own_account when action in [:new, :create, :google])

  def new(conn, params) do
    render_new(conn, Auth.account_return_to(params["return_to"]))
  end

  def create(conn, params) do
    user = conn.assigns.current_scope.user
    return_to = Auth.account_return_to(params["return_to"])

    # The password first, so a wrong one doesn't use up a recovery code.
    with {:allow, _data} <- Attack.confirm_identity_throttle(user.id),
         true <- User.valid_password?(user, params["password"] || ""),
         :ok <- check_two_factor(user, params["code"]) do
      conn
      |> Auth.mark_authenticated()
      |> redirect(to: return_to)
    else
      {:block, _data} -> too_many_tries(conn, return_to)
      false -> render_new(conn, return_to, "That password isn't right.")
      {:error, reason} -> render_new(conn, return_to, two_factor_error(reason))
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

    with {:ok, intent} <- google_intent(user, params["intent"], Auth.recently_authenticated?(conn)),
         {:ok, held} <- check_code_before_google(user, intent, params["code"]) do
      conn
      |> put_session(
        :google_intent,
        Map.merge(held, %{
          "action" => intent,
          "user_id" => user.id,
          "return_to" => return_to,
          "started_at" => System.os_time(:second)
        })
      )
      |> redirect(to: ~p"/auth/google?#{[prompt: "select_account", login_hint: user.email]}")
    else
      # Connecting adds a way into the account, so it needs a recent sign-in
      # like removing one does.
      :confirm_first ->
        redirect(conn, to: ~p"/account/confirm?#{[return_to: return_to]}")

      :error ->
        conn
        |> put_flash(:error, "Google sign-in isn't available for your account.")
        |> redirect(to: return_to)

      {:block, _data} ->
        too_many_tries(conn, return_to)

      {:error, reason} ->
        render_new(conn, return_to, two_factor_error(reason))
    end
  end

  # Confirming with Google, for an account with two-factor on, needs its code
  # first. Connecting already needs a recent sign-in, which had the code.
  #
  # A recovery code isn't used up until Google has confirmed, so going back
  # from Google, or choosing the wrong account there, doesn't cost one: it is
  # held in the intent for `NervesHubWeb.OAuthController` to use up.
  defp check_code_before_google(user, "confirm", code) do
    if TwoFactor.enabled?(user) do
      with {:allow, _data} <- Attack.confirm_identity_throttle(user.id) do
        case TwoFactor.verify_and_hold(user, code || "") do
          {:ok, :totp} -> {:ok, %{}}
          {:ok, {:held_recovery_code, held}} -> {:ok, %{"recovery_code" => held}}
          {:error, _reason} = error -> error
        end
      end
    else
      {:ok, %{}}
    end
  end

  defp check_code_before_google(_user, _intent, _code), do: {:ok, %{}}

  defp check_two_factor(user, code) do
    if TwoFactor.enabled?(user) do
      case TwoFactor.verify(user, code || "") do
        {:ok, _how} -> :ok
        {:error, _reason} = error -> error
      end
    else
      :ok
    end
  end

  defp two_factor_error(:invalid_code), do: "That code didn't work. Check your authenticator app and try again."

  defp two_factor_error(:secret_unreadable),
    do: "Codes from your authenticator app can't be checked on this server right now. Use a recovery code instead."

  defp too_many_tries(conn, return_to) do
    conn
    |> put_status(:too_many_requests)
    |> render_new(return_to, "Too many tries. To keep your account safe, wait ten minutes, then try again.")
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
      two_factor?: TwoFactor.enabled?(conn.assigns.current_scope.user),
      error: error
    )
  end
end
