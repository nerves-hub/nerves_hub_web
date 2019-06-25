defmodule NervesHubWWWWeb.PasswordResetController do
  use NervesHubWWWWeb, :controller

  alias NervesHubWWW.Accounts.Email
  alias NervesHubWebCore.Accounts.User
  alias NervesHubWebCore.Accounts.PasswordReset
  alias NervesHubWebCore.Accounts
  alias NervesHubWWW.Mailer

  alias Ecto.Changeset

  def new(conn, _params) do
    conn
    |> render("new.html", changeset: PasswordReset.changeset(%PasswordReset{}, %{}))
  end

  def create(conn, params) do
    params
    |> Map.get("password_reset", %{})
    |> Map.get("email")
    |> case do
      e when is_binary(e) and e != "" ->
        Accounts.update_password_reset_token(e)
        |> case do
          {:ok, user} ->
            Email.forgot_password(user)
            |> Mailer.deliver_later()

            :ok

          {:error, _} ->
            :ok
        end

        conn
        |> put_flash(:info, "Please check your email in order to reset your password.")
        |> redirect(to: Routes.session_path(conn, :new))

      _ ->
        conn
        |> put_flash(:error, "You must enter an email address.")
        |> render("new.html", changeset: PasswordReset.changeset(%PasswordReset{}, %{}))
    end
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

  def reset(conn, params) do
    params["token"]
    |> Accounts.reset_password(params["user"])
    |> case do
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
        |> render("new_password_form.html", token: params["token"], changeset: changeset)
    end
  end
end
