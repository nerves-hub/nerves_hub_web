defmodule NervesHubWeb.TenantController do
  use NervesHubWeb, :controller

  alias Ecto.Changeset
  alias NervesHub.Accounts.Email
  alias NervesHubCore.Accounts
  alias NervesHubCore.Accounts.{Invite, TenantKey}
  alias NervesHub.Mailer

  def edit(%{assigns: %{tenant: tenant}} = conn, _params) do
    render(
      conn,
      "edit.html",
      tenant_changeset: %Changeset{data: tenant},
      tenant_key_changeset: %Changeset{data: %TenantKey{}},
      tenant: tenant
    )
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
        render(
          conn,
          "edit.html",
          tenant_changeset: changeset,
          tenant_key_changeset: %Changeset{data: %TenantKey{}},
          tenant: tenant
        )
    end
  end

  def create_key(%{assigns: %{tenant: tenant}} = conn, %{"tenant_key" => tenant_key_params}) do
    tenant_key_params
    |> Map.put("tenant_id", tenant.id)
    |> Accounts.create_tenant_key()
    |> case do
      {:ok, _tenant_key} ->
        conn
        |> put_flash(:info, "Tenant Key Added")
        |> redirect(to: "/tenant")

      {:error, changeset} ->
        render(
          conn,
          "edit.html",
          render(
            conn,
            "edit.html",
            tenant_changeset: %Changeset{data: tenant},
            tenant_key_changeset: changeset,
            tenant: tenant
          )
        )
    end
  end

  def invite(%{assigns: %{tenant: tenant}} = conn, _params) do
    render(conn, "invite.html", changeset: %Changeset{data: %Invite{}}, tenant: tenant)
  end

  def send_invite(%{assigns: %{tenant: tenant}} = conn, %{"invite" => invite_params}) do
    invite_params
    |> Accounts.invite(tenant)
    |> case do
      {:ok, invite} ->
        Email.invite(invite, tenant)
        |> Mailer.deliver_later()

        {:ok, invite}

        conn
        |> put_flash(:info, "User has been invited")
        |> redirect(to: "/tenant")

      {:error, changeset} ->
        render(conn, "invite.html", changeset: changeset)
    end
  end
end
