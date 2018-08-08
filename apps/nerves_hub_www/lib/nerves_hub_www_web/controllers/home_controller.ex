defmodule NervesHubWWWWeb.HomeController do
  use NervesHubWWWWeb, :controller

  def index(conn, _params) do
    conn
    |> put_layout("home.html")
    |> render("index.html")
  end
end
