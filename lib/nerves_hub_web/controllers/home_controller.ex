defmodule NervesHubWeb.HomeController do
  use NervesHubWeb, :controller

  def index(conn, _params) do
    conn
    |> assign(:home?, true)
    |> render("index.html")
  end
end
