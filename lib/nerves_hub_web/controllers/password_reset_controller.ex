defmodule NervesHubWeb.PasswordResetController do
  use NervesHubWeb, :controller

  alias NervesHub.Accounts
  alias NervesHub.Accounts.PasswordReset
  alias NervesHub.Accounts.User

  alias NervesHubWeb.Auth

  plug(:get_user_by_reset_password_token when action in [:edit, :update])

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, %{"user" => %{"email" => email}}) do
    _ =
      case Accounts.get_user_by_email(email) do
        {:ok, user} ->
          Accounts.deliver_user_reset_password_instructions(
            user,
            &url(~p"/password-reset/#{&1}")
          )

        _ ->
          nil
      end

    render(conn, :instructions_sent)
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "You must enter an email address.")
    |> render(:new, changeset: PasswordReset.changeset(%PasswordReset{}, %{}))
  end

  def edit(%{assigns: %{user: user}} = conn, _params) do
    changeset = User.password_changeset(user, %{}, hash_password: false)

    render(conn, :edit, changeset: changeset)
  end

  def update(%{assigns: %{user: user}} = conn, %{"user" => user_params}) do
    case Accounts.reset_user_password(user, user_params) do
      {:ok, updated_user} ->
        conn
        |> put_flash(:info, "Password reset successfully.")
        |> Auth.log_in_user(updated_user, user_params)

      {:error, changeset} ->
        render(conn, :edit, changeset: changeset)
    end
  end

  defp get_user_by_reset_password_token(conn, _opts) do
    %{"token" => token} = conn.params

    if user = Accounts.get_user_by_reset_password_token(token) do
      conn |> assign(:user, user) |> assign(:token, token)
    else
      conn
      |> put_flash(:error, "Reset password link is invalid or it has expired.")
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end
end
