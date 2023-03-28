defmodule NervesHubWeb.HomeController do
  use NervesHubWeb, :controller

  def index(conn, _params) do
    case conn.assigns do
      %{user: user} ->
        redirect(conn, to: Routes.product_path(conn, :index, user.username))

      _ ->
        redirect(conn, to: Routes.session_path(conn, :new))
    end
  end
end
