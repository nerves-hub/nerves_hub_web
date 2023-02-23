defmodule NervesHubWeb.HomeController do
  use NervesHubWeb, :controller

  def index(conn, _params) do
    conn
    |> render("index.html")
  end
end
