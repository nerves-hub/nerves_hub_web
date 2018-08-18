defmodule NervesHubWWWWeb.SessionController do
  use NervesHubWWWWeb, :controller

  alias Ecto.Changeset
  alias NervesHubCore.Accounts
  alias NervesHubCore.Accounts.User

  @session_key "auth_user_id"

  def new(conn, _params) do
    conn
    |> get_session(@session_key)
    |> case do
      nil ->
        render(conn, "new.html", changeset: %Changeset{data: %User{}}, layout: false)

      _ ->
        conn
        |> redirect(to: dashboard_path(conn, :index))
    end
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    email
    |> Accounts.authenticate(password)
    |> case do
      {:ok, %User{id: user_id}} ->
        conn
        |> put_session(@session_key, user_id)
        |> render_success

      {:error, :authentication_failed} ->
        conn
        |> put_flash(:error, "Login Failed")
        |> render_error("new.html", changeset: %Changeset{data: %User{}})
    end
  end

  def delete(conn, _params) do
    conn
    |> delete_session(@session_key)
    |> redirect(to: "/")
  end
end
