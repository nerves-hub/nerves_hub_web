defmodule NervesHubWWWWeb.OrgUserController do
  use NervesHubWWWWeb, :controller

  alias NervesHubWebCore.Accounts

  def index(%{assigns: %{org: org}} = conn, _params) do
    conn
    |> render(
      "index.html",
      org_users: Accounts.get_org_users(org)
    )
  end
end
