defmodule NervesHubWeb.HomeController do
  use NervesHubWeb, :controller

  plug(:require_no_permission, :sends_the_user_to_their_organizations when action in [:index])

  def index(conn, _params) do
    redirect(conn, to: ~p"/orgs")
  end
end
