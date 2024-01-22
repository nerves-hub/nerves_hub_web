defmodule NervesHubWeb.HomeController do
  use NervesHubWeb, :controller

  def index(conn, _params) do
    case Map.has_key?(conn.assigns, :user) && !is_nil(conn.assigns.user) do
      true ->
        render(conn, "index.html")

      false ->
        redirect(conn, to: Routes.session_path(conn, :new))
    end
  end

  def error(_conn, _params) do
    raise "Error"
  end

  def online_devices(conn, _params) do
    render(conn, "online_devices.html", devices: [])
  end
end
