defmodule NervesHubWeb.Plugs.EnsureAuthenticated do
  import Plug.Conn

  use NervesHubWeb, :verified_routes

  alias Phoenix.Controller

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    case get_session(conn, "auth_user_id") do
      nil ->
        conn
        |> delete_session("auth_user_id")
        |> put_session("login_redirect_path", conn.request_path)
        |> Controller.put_flash(:error, "You must login to access this page.")
        |> Controller.redirect(to: ~p"/login")
        |> halt()

      _user_id ->
        conn
    end
  end
end
