defmodule NervesHubWeb.SessionController do
  use NervesHubWeb, :controller

  alias NervesHub.Accounts
  alias NervesHub.Accounts.User
  alias NervesHub.Accounts.UserNotifier
  alias NervesHub.Accounts.UserToken
  alias NervesHubWeb.Auth

  @max_mfa_attempts 8

  def new(conn, params) do
    form = Phoenix.Component.to_form(%{}, as: "User")

    render(conn, :new, form: form, message: params["message"])
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password} = user_params}) do
    case Accounts.get_user_by_email_and_password(email, password) do
      %User{confirmed_at: nil} = user ->
        resend_confirmation_email(
          conn,
          user,
          "Before you login you need to confirm your email address. A new link has been sent to your email."
        )

      %User{} = user ->
        if Accounts.mfa_enabled?(user) do
          begin_mfa_login(conn, user, user_params)
        else
          conn
          |> put_flash(:info, "Welcome back!")
          |> Auth.log_in_user(user, user_params)
        end

      _ ->
        form = Phoenix.Component.to_form(user_params, as: "user")

        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> assign(:error_message, "Invalid email or password")
        |> render(:new, form: form)
    end
  end

  def mfa_new(conn, _params) do
    if pending_mfa_user_id(conn) do
      render(conn, :mfa, form: Phoenix.Component.to_form(%{}, as: "mfa"))
    else
      conn
      |> put_flash(:error, "Please sign in before entering an authentication code.")
      |> redirect(to: ~p"/login")
    end
  end

  def mfa_create(conn, %{"mfa" => mfa_params}) do
    code = first_present_code(mfa_params)

    with user_id when not is_nil(user_id) <- pending_mfa_user_id(conn),
         user = Accounts.get_user!(user_id),
         {:ok, _method} <- Accounts.verify_mfa_code(user, code) do
      params = get_session(conn, :mfa_login_params) || %{}

      conn
      |> delete_session(:mfa_user_id)
      |> delete_session(:mfa_started_at)
      |> delete_session(:mfa_login_params)
      |> put_flash(:info, "Welcome back!")
      |> Auth.log_in_user(user, params)
    else
      _ ->
        handle_invalid_mfa_attempt(conn)
    end
  end

  def confirm(conn, %{"token" => token}) do
    with {:token_fetched, {:ok, user, user_token}} <-
           {:token_fetched, Accounts.fetch_user_by_confirm_token(token)},
         {:token_valid, true, _user} <-
           {:token_valid, UserToken.token_still_valid?(:confirm, user_token), user},
         {:user_confirmed, {:ok, user}, _} <-
           {:user_confirmed, Accounts.confirm_user(user), user},
         {:ok, _} <- UserNotifier.deliver_welcome_email(user) do
      conn
      |> put_flash(:info, "Welcome to NervesHub!")
      |> Auth.log_in_user(user)
    else
      {:token_valid, false, user} ->
        resend_confirmation_email(
          conn,
          user,
          "It looks like your confirmation link has expired. A new link has been sent to your email."
        )

      {:user_confirmed, :error, user} ->
        resend_confirmation_email(
          conn,
          user,
          "An unexpected error occurred. A new link has been sent to your email."
        )

      {:token_fetched, :error} ->
        conn
        |> assign(:error_title, "The token was invalid or expired")
        |> display_confirmation_error("We couldn't find the token for confirming your account.")
    end
  end

  def cli(conn, %{"token" => token}) do
    conn.assigns.current_scope.user
    |> Accounts.cli_session_waiting?(token)
    |> case do
      {:ok, %{status: :ready}} ->
        conn
        |> assign(:page_title, "CLI Session Confirmed")
        |> render(:cli_confirmed)

      {:ok, cli_session} ->
        conn
        |> assign(:page_title, "CLI Session Confirmation")
        |> assign(:token, token)
        |> assign(:confirmation_code, cli_session.confirmation_code)
        |> render(:cli)

      {:error, _} ->
        render(conn, :cli_invalid)
    end
  end

  def cli_confirm(conn, %{"token" => token}) do
    conn.assigns.current_scope.user
    |> Accounts.verify_cli_session_token(token)
    |> case do
      :ok ->
        redirect(conn, to: ~p"/auth/cli/#{token}")

      {:error, :not_found} ->
        raise NervesHubWeb.NotFoundError
    end
  end

  defp resend_confirmation_email(conn, user, message) do
    {:ok, _} =
      Accounts.deliver_user_confirmation_instructions(
        user,
        &url(~p"/confirm/#{&1}")
      )

    display_confirmation_error(conn, message)
  end

  def begin_mfa_login(conn, %User{} = user, params \\ %{}) do
    conn
    |> put_session(:mfa_user_id, user.id)
    |> put_session(:mfa_started_at, System.system_time(:second))
    |> put_session(:mfa_attempt_count, 0)
    |> put_session(:mfa_login_params, Map.take(params, ["remember_me"]))
    |> redirect(to: ~p"/login/mfa")
  end

  defp pending_mfa_user_id(conn) do
    started_at = get_session(conn, :mfa_started_at)

    if is_integer(started_at) and System.system_time(:second) - started_at <= 300 do
      get_session(conn, :mfa_user_id)
    end
  end

  defp first_present_code(mfa_params) do
    [mfa_params["code"], mfa_params["recovery_code"]]
    |> Enum.map(&String.trim(&1 || ""))
    |> Enum.find("", &(&1 != ""))
  end

  defp handle_invalid_mfa_attempt(conn) do
    attempt_count = get_session(conn, :mfa_attempt_count) || 0
    next_attempt_count = attempt_count + 1

    if next_attempt_count >= @max_mfa_attempts do
      conn
      |> clear_pending_mfa()
      |> put_flash(:error, "Too many invalid authentication codes. Please sign in again.")
      |> redirect(to: ~p"/login")
    else
      conn
      |> put_session(:mfa_attempt_count, next_attempt_count)
      |> assign(:error_message, "Invalid authentication code")
      |> render(:mfa, form: Phoenix.Component.to_form(%{}, as: "mfa"))
    end
  end

  defp clear_pending_mfa(conn) do
    conn
    |> delete_session(:mfa_user_id)
    |> delete_session(:mfa_started_at)
    |> delete_session(:mfa_attempt_count)
    |> delete_session(:mfa_login_params)
  end

  defp display_confirmation_error(conn, error_message) do
    conn
    |> assign(:error_message, error_message)
    |> render(:confirm_error)
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> NervesHubWeb.Auth.log_out_user()
  end
end
