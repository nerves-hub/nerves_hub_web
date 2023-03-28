defmodule NervesHubWeb.SessionController do
  use NervesHubWeb, :controller

  alias NervesHub.Accounts

  @session_key "auth_user_id"

  def new(conn, _params) do
    conn
    |> get_session(@session_key)
    |> case do
      nil ->
        render(conn, "new.html")

      user_id ->
        case Accounts.get_user(user_id) do
          {:ok, _user} ->
            redirect(conn, to: Routes.home_path(conn, :index))

          _ ->
            render(conn, "new.html")
        end
    end
  end

  def create(conn, %{
        "login" => %{"email_or_username" => email_or_username, "password" => password}
      }) do
    email_or_username
    |> Accounts.authenticate(password)
    |> render_create_session(conn)
  end

  def delete(conn, _params) do
    conn
    |> delete_session(@session_key)
    |> redirect(to: "/")
  end

  defp render_create_session(account, conn) do
    case account do
      {:ok, user} ->
        conn
        |> put_session(@session_key, user.id)
        |> redirect(to: redirect_path_after_login(conn, user))

      {:error, :authentication_failed} ->
        conn
        |> put_flash(:error, "Login Failed")
        |> redirect(to: Routes.session_path(conn, :new))
    end
  end

  defp redirect_path_after_login(conn, user) do
    get_session(conn, :login_redirect_path) || Routes.home_path(conn, :index)
  end
end
