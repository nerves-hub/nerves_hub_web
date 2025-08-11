defmodule NervesHubWeb.Plugs.EnsureAuthenticated do
  import Plug.Conn

  use NervesHubWeb, :verified_routes

  alias Phoenix.Controller

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    case get_session(conn, :user_token) do
      nil ->
        conn
        |> put_session("login_redirect_path", conn.request_path)
        |> Controller.put_flash(:error, "You must login to access this page.")
        |> Controller.redirect(to: ~p"/login")
        |> halt()

      _user_token ->
        conn
    end
  end
end
