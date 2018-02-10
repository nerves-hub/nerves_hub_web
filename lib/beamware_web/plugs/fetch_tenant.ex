defmodule BeamwareWeb.Plugs.FetchTenant do
  import Plug.Conn

  alias Beamware.Accounts

  def init(opts) do
    opts
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
