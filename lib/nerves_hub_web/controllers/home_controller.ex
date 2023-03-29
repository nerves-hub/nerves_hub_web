defmodule NervesHubWeb.HomeController do
  use NervesHubWeb, :controller

  alias NervesHub.Accounts

  def index(conn, _params) do
    case Map.has_key?(conn.assigns, :user) && !is_nil(conn.assigns.user) do
      true ->
        render(conn, "index.html")

      false ->
        redirect(conn, to: Routes.session_path(conn, :new))
    end
  end
end
