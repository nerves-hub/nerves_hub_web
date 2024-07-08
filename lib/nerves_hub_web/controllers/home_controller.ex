defmodule NervesHubWeb.HomeController do
  use NervesHubWeb, :controller

  alias NervesHubWeb.AccountController

  def index(conn, _params) do
    conn
    |> AccountController.maybe_show_invites()
    |> redirect(to: ~p"/orgs")
  end
end
