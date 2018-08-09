defmodule NervesHubAPIWeb.UserController do
  use NervesHubAPIWeb, :controller

  alias NervesHubCore.Accounts

  action_fallback(NervesHubAPIWeb.FallbackController)

  def me(%{assigns: %{user: user}} = conn, _params) do
    render(conn, "show.json", user: user)
  end

  def register(conn, params) do
    params = Map.put(params, "org_name", params["name"])

    with {:ok, {_org, user}} <- Accounts.create_org_with_user(params) do
      render(conn, "show.json", user: user)
    end
  end
end
