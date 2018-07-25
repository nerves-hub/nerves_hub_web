defmodule NervesHubAPIWeb.UserController do
  use NervesHubAPIWeb, :controller

  action_fallback NervesHubAPIWeb.FallbackController

  def me(%{assigns: %{user: user}} = conn, _params) do
    render(conn, "show.json", user: user)
  end

end
