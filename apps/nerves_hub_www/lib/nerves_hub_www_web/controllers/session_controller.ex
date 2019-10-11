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
            redirect(conn, to: Routes.product_path(conn, :index, user.username))

          _ ->
            render(conn, "new.html")
        end
    end
  end

  def create(conn, %{"login" => %{"email" => email, "password" => password}}) do
    email
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
<<<<<<< HEAD

  def delete(conn, _params) do
    conn
    |> delete_session(@session_key)
    |> redirect(to: "/")
  end

  defp redirect_path_after_login(conn, user) do
    get_session(conn, :login_redirect_path) || Routes.product_path(conn, :index, user.username)
  end
=======
>>>>>>> Allow authenticating with username instea of email
end
