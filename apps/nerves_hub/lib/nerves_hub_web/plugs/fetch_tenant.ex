defmodule NervesHubWeb.Plugs.FetchTenant do
  import Plug.Conn

  alias NervesHubCore.Accounts

  def init(opts) do
    opts
  end

  def call(%{params: %{"tenant_id" => tenant_id}} = conn, _opts) do
    tenant = Accounts.get_tenant(tenant_id)

    conn
    |> assign(:tenant, tenant)
  end

  def call(%{assigns: %{user: user}} = conn, _opts) do
    user.tenant_id
    |> Accounts.get_tenant()
    |> case do
      {:ok, tenant} ->
        conn
        |> assign(:tenant, tenant)

      _ ->
        conn
        |> halt()
    end
  end
end
