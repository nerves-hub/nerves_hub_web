defmodule NervesHubWeb.SessionController do
  use NervesHubWeb, :controller

  alias NervesHub.Accounts
  alias NervesHub.Accounts.TwoFactor
  alias NervesHub.Accounts.User
  alias NervesHub.Accounts.UserNotifier
  alias NervesHub.Accounts.UserToken
  alias NervesHubWeb.Auth
  alias NervesHubWeb.Helpers.ClientIP
  alias NervesHubWeb.Plugs.Attack

  plug(
    :require_no_permission,
    :signs_the_user_in when action in [:new, :create, :confirm, :cli, :cli_code, :cli_confirm, :cli_confirmed]
  )

  # The second step of a password sign-in. `fetch_pending_two_factor_user`
  # turns away anyone who didn't pass the first.
  plug(
    :require_no_permission,
    :finishes_a_password_sign_in when action in [:two_factor, :verify_two_factor, :cancel_two_factor]
  )

  plug(:require_no_permission, :signs_the_user_out when action in [:delete])
  plug(:limit_cli_code_attempts when action in [:cli_code, :cli_confirm])
  plug(:fetch_pending_two_factor_user when action in [:two_factor, :verify_two_factor])
  plug(:limit_two_factor_attempts when action in [:verify_two_factor])

  def new(conn, params) do
    conn = maybe_store_external_return_to(conn, params["return_to"])
    form = Phoenix.Component.to_form(%{}, as: "User")

    render(conn, :new, form: form, message: params["message"])
  end

  # Persist an allow-listed external `return_to` (e.g. the nerves_hub_mcp OAuth
  # consent URL) so the user lands back there after logging in. Same-app returns
  # are already handled by `Auth.require_authenticated_user`.
  defp maybe_store_external_return_to(conn, return_to) do
    case Auth.return_to_target(return_to) do
      {:external, url} -> put_session(conn, :login_redirect_path, url)
      _ -> conn
    end
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
        Auth.sign_in(conn, user, user_params, flash: "Welcome back!", link_google: true)

      _ ->
        # Keep the email and the remember-me tick, but never send the password back.
        form = Phoenix.Component.to_form(Map.delete(user_params, "password"), as: "user")

        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> assign(:error_message, "That email and password don't match")
        |> render(:new, form: form)
    end
  end

  # The second step of signing in, for a user with two-factor on. Their
  # password (or Google, or a password reset) got them here, and
  # `Auth.sign_in/4` left what's needed to finish in the session.

  def two_factor(conn, params), do: render_two_factor(conn, mode: two_factor_mode(params))

  def verify_two_factor(conn, params) do
    user = conn.assigns.pending_user

    case TwoFactor.verify(user, params["code"] || "") do
      {:ok, :totp} ->
        Auth.complete_two_factor(conn, user)

      {:ok, {:recovery_code, left}} ->
        Auth.complete_two_factor(conn, user, recovery_code_message(left))

      {:error, :invalid_code} ->
        mode = two_factor_mode(params)
        render_two_factor(conn, mode: mode, error: {"That code didn't work", wrong_code_detail(mode)})

      # The server's encryption key has changed since the app was set up. A
      # recovery code doesn't need the secret, so the page opens on that.
      {:error, :secret_unreadable} ->
        render_two_factor(conn,
          mode: :recovery,
          error:
            {"Your authenticator app can't be checked right now",
             "Sign in with a recovery code instead, then set your app up again. Without one, ask your platform admin for help."}
        )
    end
  end

  def cancel_two_factor(conn, _params) do
    conn
    |> Auth.cancel_two_factor()
    |> redirect(to: ~p"/login")
  end

  # Which field the code page opens with: the code from the app, or a
  # recovery code. Either field takes either kind of code; this only picks
  # what the page asks for.
  defp two_factor_mode(%{"mode" => "recovery"}), do: :recovery
  defp two_factor_mode(_params), do: :app

  defp wrong_code_detail(:app), do: "Check the code your app shows now and try again."
  defp wrong_code_detail(:recovery), do: "Check it against the codes you saved. Each one works only once."

  defp recovery_code_message(0) do
    "You signed in with your last recovery code. Make new ones in your account settings."
  end

  defp recovery_code_message(1), do: "You signed in with a recovery code. You have 1 left."
  defp recovery_code_message(left), do: "You signed in with a recovery code. You have #{left} left."

  defp fetch_pending_two_factor_user(conn, _opts) do
    case Auth.pending_two_factor_user(conn) do
      {:ok, user} ->
        assign(conn, :pending_user, user)

      :error ->
        conn
        |> Auth.cancel_two_factor()
        |> put_flash(:error, "Your sign-in timed out. Sign in again.")
        |> redirect(to: ~p"/login")
        |> halt()
    end
  end

  defp limit_two_factor_attempts(conn, _opts) do
    case Attack.two_factor_throttle(conn.assigns.pending_user.id) do
      {:allow, _data} ->
        conn

      {:block, _data} ->
        conn
        |> put_status(:too_many_requests)
        |> render_two_factor(
          error: {"Too many codes tried", "To keep your account safe, wait ten minutes, then try again."},
          mode: two_factor_mode(conn.params),
          locked: true
        )
        |> halt()
    end
  end

  defp render_two_factor(conn, opts) do
    {message, detail} = Keyword.get(opts, :error, {nil, nil})

    conn
    |> assign(:page_title, "Two-factor authentication")
    |> assign(:email, conn.assigns.pending_user.email)
    |> assign(:error_message, message)
    |> assign(:error_detail, detail)
    |> assign(:locked, Keyword.get(opts, :locked, false))
    |> assign(:mode, Keyword.get(opts, :mode, :app))
    |> render(:two_factor)
  end

  def confirm(conn, %{"token" => token}) do
    with {:token_fetched, {:ok, user, user_token}} <-
           {:token_fetched, Accounts.fetch_user_by_confirm_token(token)},
         {:token_valid, true, _user} <-
           {:token_valid, UserToken.token_still_valid?(:confirm, user_token), user},
         {:user_confirmed, {:ok, user}, _} <-
           {:user_confirmed, Accounts.confirm_user(user), user},
         {:ok, _} <- UserNotifier.deliver_welcome_email(user) do
      # Following the link proves whoever followed it reads the address, not
      # that they chose the account's password. Someone else may have: an org
      # admin can register an invitee from the invite link the members page
      # shows. Signing in here would hand the address's owner an account the
      # other person can still use, so only a session that is already this
      # account's carries on. Anyone else signs in, and someone who never set
      # the password resets it, which ends every other session and API token.
      if signed_in_as?(conn, user) do
        conn
        |> put_flash(:info, "Welcome to NervesHub!")
        |> redirect(to: ~p"/orgs")
      else
        conn
        |> put_flash(:info, "Your email address is confirmed. Sign in to continue.")
        |> redirect(to: ~p"/login")
      end
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

  # CLI login. The CLI shows its user a code and this page's address, and they
  # type the code in here. Nothing in a link can find a login, so someone who
  # starts one can't send a link to a person signed in and have them confirm it
  # with a click. The confirmation page says when and where the login started,
  # for anyone who was handed a code to type in anyway.

  @cli_code_not_found "That code doesn't match a sign-in waiting to be confirmed. Check it against the code in your terminal. Codes last five minutes."

  def cli(conn, _params) do
    render_cli_code(conn)
  end

  def cli_code(conn, %{"code" => code}) do
    case Accounts.find_cli_session_by_code(conn.assigns.current_scope.user, code) do
      {:ok, %{status: :waiting} = cli_session} ->
        requested_from = cli_session.requested_from
        browser_address = ClientIP.request_address(conn)

        conn
        |> assign(:page_title, "Confirm the CLI sign-in")
        |> assign(:code, code)
        |> assign(:note, cli_session.note)
        |> assign(:requested_at, DateTime.from_unix!(cli_session.requested_at))
        |> assign(:requested_from, requested_from)
        |> assign(:browser_address, browser_address)
        |> assign(:other_address?, requested_from not in [nil, browser_address])
        |> render(:cli_confirm)

      {:ok, _already_confirmed} ->
        redirect(conn, to: ~p"/auth/cli/confirmed")

      {:error, :not_found} ->
        render_cli_code(conn, @cli_code_not_found)
    end
  end

  def cli_confirm(conn, %{"code" => code}) do
    user = conn.assigns.current_scope.user

    with {:ok, cli_session} <- Accounts.find_cli_session_by_code(user, code),
         :ok <- confirm_cli_session(user, cli_session) do
      redirect(conn, to: ~p"/auth/cli/confirmed")
    else
      {:error, _reason} -> render_cli_code(conn, @cli_code_not_found)
    end
  end

  def cli_confirmed(conn, _params) do
    conn
    |> assign(:page_title, "Signed in to the CLI")
    |> render(:cli_confirmed)
  end

  defp confirm_cli_session(user, %{status: :waiting, token: token}), do: Accounts.verify_cli_session_token(user, token)

  defp confirm_cli_session(_user, _already_confirmed), do: :ok

  defp limit_cli_code_attempts(conn, _opts) do
    case Attack.cli_code_throttle(conn.assigns.current_scope.user.id) do
      {:allow, _data} ->
        conn

      {:block, _data} ->
        conn
        |> render_cli_code("Too many codes tried. Wait ten minutes, then run the login command in your terminal again.")
        |> halt()
    end
  end

  defp render_cli_code(conn, error_message \\ nil) do
    conn
    |> assign(:page_title, "Sign in to the CLI")
    |> assign(:error_message, error_message)
    |> render(:cli)
  end

  defp signed_in_as?(conn, %User{id: id}) do
    match?(%{user: %User{id: ^id}}, conn.assigns[:current_scope])
  end

  defp resend_confirmation_email(conn, user, message) do
    {:ok, _} =
      Accounts.deliver_user_confirmation_instructions(
        user,
        &url(~p"/confirm/#{&1}")
      )

    display_confirmation_error(conn, message)
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
