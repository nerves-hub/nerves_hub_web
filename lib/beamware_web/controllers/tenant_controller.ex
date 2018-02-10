defmodule BeamwareWeb.TenantController do
  use BeamwareWeb, :controller

  alias Ecto.Changeset
  alias Beamware.Accounts

  plug BeamwareWeb.Plugs.FetchTenant

  def edit(%{assigns: %{tenant: tenant}} = conn, _params) do
    render(conn, "edit.html", changeset: %Changeset{data: tenant})
  end

  def update(%{assigns: %{tenant: tenant}} = conn, %{"tenant" => tenant_params}) do
    tenant
    |> Accounts.update_tenant(tenant_params)
    |> case do
      {:ok, _tenant} ->
        conn
        |> put_flash(:info, "Tenant Updated")
        |> redirect(to: "/tenant")

      {:error, changeset} ->
        render(conn, "edit.html", changeset: changeset)
    end
  end
end
