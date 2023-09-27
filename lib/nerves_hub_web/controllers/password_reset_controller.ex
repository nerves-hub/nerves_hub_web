defmodule NervesHubWeb.PasswordResetController do
  use NervesHubWeb, :controller

  alias NervesHub.Accounts.SwooshEmail
  alias NervesHub.Accounts.User
  alias NervesHub.Accounts.PasswordReset
  alias NervesHub.Accounts
  alias NervesHub.SwooshMailer

  alias Ecto.Changeset

  def new(conn, _params) do
    conn
    |> render("new.html", changeset: PasswordReset.changeset(%PasswordReset{}, %{}))
  end

  def create(conn, %{"password_reset" => %{"email" => email}})
      when is_binary(email) and email != "" do
    case Accounts.update_password_reset_token(email) do
      {:ok, user} ->
        user
        |> SwooshEmail.forgot_password()
        |> SwooshMailer.deliver()

        :ok

      {:error, _} ->
        :ok
    end

    conn
    |> put_flash(:info, "Please check your email in order to reset your password.")
    |> redirect(to: Routes.session_path(conn, :new))
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "You must enter an email address.")
    |> render("new.html", changeset: PasswordReset.changeset(%PasswordReset{}, %{}))
  end

  def new_password_form(conn, params) do
    params["token"]
    |> Accounts.get_user_with_password_reset_token()
    |> case do
      {:ok, user} ->
        conn
        |> render(
          "new_password_form.html",
          token: user.password_reset_token,
          changeset: User.update_changeset(user, %{})
        )

      {:error, :not_found} ->
        conn
        |> put_flash(
          :warning,
          "We're sorry, your password reset link is expired. Please try again."
        )
        |> redirect(to: Routes.session_path(conn, :new))
    end
  end

  def reset(conn, %{"token" => token, "user" => user}) do
    case Accounts.reset_password(token, user) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Password reset successfully. Please log in.")
        |> redirect(to: Routes.session_path(conn, :new))

      {:error, :not_found} ->
        conn
        |> put_flash(
          :warning,
          "We're sorry, your password reset link is expired or incorrect. Please try again."
        )
        |> redirect(to: Routes.session_path(conn, :new))

      {:error, %Changeset{} = changeset} ->
        conn
        |> put_flash(:error, "You must provide a new password.")
        |> render("new_password_form.html", token: token, changeset: changeset)
    end
  end
end
