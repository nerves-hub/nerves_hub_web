defmodule BeamwareWeb.SessionController do
  use BeamwareWeb, :controller

  alias Ecto.Changeset
  alias Beamware.Accounts
  alias Beamware.Accounts.User

  @session_key "auth_user_id"

  def new(conn, _params) do
    render(conn, "new.html", changeset: %Changeset{data: %User{}})
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    email
    |> Accounts.authenticate(password)
    |> case do
      {:ok, %User{id: user_id}} ->
        conn
        |> put_session(@session_key, user_id)
        |> redirect(to: dashboard_path(conn, :index))

      {:error, :authentication_failed} ->
        conn
        |> put_flash(:error, "Login Failed")
        |> redirect(to: session_path(conn, :new))
    end
  end

  def delete(conn, _params) do
    conn
    |> delete_session(@session_key)
    |> redirect(to: "/")
  end
end
