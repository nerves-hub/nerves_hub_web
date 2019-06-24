defmodule NervesHubWWWWeb.SessionController do
  use NervesHubWWWWeb, :controller

  alias NervesHubWebCore.Accounts

  @session_key "auth_user_id"

  def new(conn, _params) do
    conn
    |> get_session(@session_key)
    |> case do
      nil ->
        render(conn, "new.html")

      user_id ->
        case Accounts.get_user(user_id) do
          {:ok, user} ->
            redirect(conn, to: product_path(conn, :index, user.username))

          _ ->
            render(conn, "new.html")
        end
    end
  end

  def create(conn, %{"login" => %{"email" => email, "password" => password}}) do
    email
    |> Accounts.authenticate(password)
    |> case do
      {:ok, user} ->
        conn
        |> put_session(@session_key, user.id)
        |> redirect(to: product_path(conn, :index, user.username))

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
