defmodule NervesHubWeb.API.Plugs.Org do
  import Plug.Conn

  alias NervesHub.Accounts

  def init(opts) do
    opts
  end

  def call(%{params: %{"org_name" => org_name}, assigns: %{user: user}} = conn, _opts) do
    org = Accounts.get_org_by_name_and_user!(org_name, user)

    assign(conn, :org, org)
  end
end
