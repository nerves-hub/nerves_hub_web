defmodule NervesHubWeb.PasswordResetController do
  use NervesHubWeb, :controller

  alias NervesHub.Accounts.User
  alias NervesHub.Accounts
  alias Ecto.Changeset

  def new(conn, _params) do
    conn
    |> render("new.html", changeset: %Changeset{data: %User{}})
  end

  def create(conn, params) do
    params
    |> Map.get("user", %{})
    |> Map.get("email")
    |> case do
      e when is_binary(e) and e != "" ->
        Accounts.send_password_reset_email(e)

        conn
        |> put_flash(:info, "Please check your email in order to reset your password.")
        |> redirect(to: session_path(conn, :new))

      _ ->
        conn
        |> render("new.html", changeset: email_required_changeset())
    end
  end

  defp email_required_changeset do
    types = %{email: :string}

    {%{}, types}
    |> Changeset.cast(%{}, types)
    |> Changeset.validate_required([:email])
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
          changeset: %Changeset{data: user}
        )

      {:error, :not_found} ->
        conn
        |> put_flash(
          :warning,
          "We're sorry, your password reset link is expired. Please try again."
        )
        |> redirect(to: session_path(conn, :new))
    end
  end

  def reset(conn, params) do
    params["token"]
    |> Accounts.reset_password(params["user"])
    |> case do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Password reset successfully. Please log in.")
        |> redirect(to: session_path(conn, :new))

      {:error, :not_found} ->
        conn
        |> put_flash(
          :warning,
          "We're sorry, your password reset link is expired or incorrect. Please try again."
        )
        |> redirect(to: session_path(conn, :new))

      {:error, %Changeset{} = changeset} ->
        conn
        |> render("new_password_form.html", token: params["token"], changeset: changeset)
    end
  end
end
