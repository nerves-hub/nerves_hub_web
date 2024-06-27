defmodule NervesHubWeb.HomeController do
  use NervesHubWeb, :controller

  alias NervesHubWeb.AccountController

  def index(conn, _params) do
    case Map.has_key?(conn.assigns, :user) && !is_nil(conn.assigns.user) do
      true ->
        conn
        |> AccountController.maybe_show_invites()
        |> render("index.html")

      false ->
        redirect(conn, to: Routes.session_path(conn, :new))
    end
  end

  def error(_conn, _params) do
    raise "Error"
  end
end
