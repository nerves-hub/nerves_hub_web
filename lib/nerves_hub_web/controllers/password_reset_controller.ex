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
            &url(~p"/password-reset/#{&1}"),
            url(~p"/login")
          )

        _ ->
          nil
      end

    render(conn, :instructions_sent, email: email)
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
      # Back to the request form, which explains why and asks for the email again.
      # Under its own flash key so it shows there rather than as a toast.
      conn
      |> put_flash(:reset_link_expired, true)
      |> redirect(to: ~p"/password-reset")
      |> halt()
    end
  end
end
