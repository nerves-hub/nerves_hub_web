defmodule NervesHubWeb.HomeController do
  use NervesHubWeb, :controller

  def index(conn, _params) do
    redirect(conn, to: ~p"/orgs")
  end
end
