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
        render(conn, "new.html", changeset: %Changeset{data: %User{}})

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
