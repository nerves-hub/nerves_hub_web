defmodule NervesHubWWWWeb.SponsorController do
  use NervesHubWWWWeb, :controller

  def index(conn, _params) do
    render(
      conn,
      "index.html"
    )
  end
end
