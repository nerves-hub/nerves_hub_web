defmodule NervesHubAPIWeb.Plugs.Org do
  import Plug.Conn

  alias NervesHubCore.Accounts

  def init(opts) do
    opts
  end

  def call(%{params: %{"org_name" => org_name}, assigns: %{user: user}} = conn, _opts) do
    case Accounts.get_org_by_name_and_user(org_name, user) do
      {:ok, org} ->
        conn
        |> assign(:org, org)

      _ ->
        conn
        |> put_resp_header("content-type", "application/json")
        |> send_resp(403, Jason.encode!(%{status: "User is not authorized for org: #{org_name}"}))
        |> halt()
    end
  end
end
