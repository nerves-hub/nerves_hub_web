defmodule NervesHubWeb.DashboardController do
  use NervesHubWeb, :controller

  def index(conn, _params) do
    conn
    |> render("index.html")
  end
end
