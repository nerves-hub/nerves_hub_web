defmodule NervesHubWeb.SessionController do
  use NervesHubWeb, :controller

  alias NervesHub.Accounts
  alias NervesHub.Accounts.User
  alias NervesHub.Accounts.UserNotifier
  alias NervesHub.Accounts.UserToken
  alias NervesHubWeb.Auth
  alias NervesHubWeb.Helpers.ClientIP
  alias NervesHubWeb.Plugs.Attack

  plug(:limit_cli_code_attempts when action in [:cli_code, :cli_confirm])

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
        conn
        |> put_flash(:info, "Welcome back!")
        |> Auth.link_pending_google_account(user)
        |> Auth.log_in_user(user, user_params)

      _ ->
        # Keep the email and the remember-me tick, but never send the password back.
        form = Phoenix.Component.to_form(Map.delete(user_params, "password"), as: "user")

        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> assign(:error_message, "That email and password don't match")
        |> render(:new, form: form)
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
