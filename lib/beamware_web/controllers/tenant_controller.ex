defmodule BeamwareWeb.TenantController do
  use BeamwareWeb, :controller

  alias Ecto.Changeset
  alias Beamware.Accounts
  alias Beamware.Accounts.Invite

  plug(BeamwareWeb.Plugs.FetchTenant)

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

  def invite(%{assigns: %{tenant: tenant}} = conn, _params) do
    render(conn, "invite.html", changeset: %Changeset{data: %Invite{}}, tenant: tenant)
  end

  def send_invite(%{assigns: %{tenant: tenant}} = conn, %{"invite" => invite_params}) do
    invite_params
    |> Accounts.invite(tenant)
    |> case do
      {:ok, _invite} ->
        conn
        |> put_flash(:info, "User has been invited")
        |> redirect(to: "/tenant")

      {:error, changeset} ->
        render(conn, "invite.html", changeset: changeset)
    end
  end
end
