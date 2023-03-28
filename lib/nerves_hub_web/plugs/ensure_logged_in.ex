defmodule NervesHubWeb.Plugs.EnsureLoggedIn do
  import Plug.Conn

  alias Phoenix.Controller

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    case Map.has_key?(conn.assigns, :user) && !is_nil(conn.assigns.user) do
      true ->
        conn

      false ->
        conn
        |> put_session(:login_redirect_path, conn.request_path)
        |> Controller.put_flash(:error, "You must login to access this page.")
        |> Controller.redirect(to: "/")
        |> halt()
    end
  end
end
