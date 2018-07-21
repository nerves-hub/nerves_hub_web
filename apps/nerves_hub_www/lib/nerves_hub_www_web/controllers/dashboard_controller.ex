defmodule NervesHubWWWWeb.DashboardController do
  use NervesHubWWWWeb, :controller

  def index(conn, _params) do
    conn
    |> render("index.html")
  end
end
