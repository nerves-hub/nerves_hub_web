defmodule NervesHubWeb.SessionController do
  use NervesHubWeb, :controller

  alias NervesHub.Accounts
  alias NervesHub.Accounts.User
  alias NervesHub.Accounts.UserNotifier
  alias NervesHub.Accounts.UserToken
  alias NervesHubWeb.Auth

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
        conn
        |> put_flash(:info, "Welcome back!")
        |> Auth.log_in_user(user, user_params)

      _ ->
        form = Phoenix.Component.to_form(user_params, as: "user")

        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> assign(:error_message, "Invalid email or password")
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
      conn =
        case Accounts.bootstrap_user(user) do
          {:ok, %{org: org, product: product}} ->
            put_session(conn, :login_redirect_path, ~p"/org/#{org.name}/#{product.name}/devices")

          _ ->
            conn
        end

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
