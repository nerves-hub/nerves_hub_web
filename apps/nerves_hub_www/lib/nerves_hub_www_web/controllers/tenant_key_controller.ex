defmodule NervesHubWWWWeb.TenantKeyController do
  use NervesHubWWWWeb, :controller

  alias NervesHubCore.Accounts
  alias NervesHubCore.Accounts.TenantKey

  def index(%{assigns: %{tenant: tenant}} = conn, _params) do
    tenant_keys = Accounts.list_tenant_keys(tenant)
    render(conn, "index.html", tenant_keys: tenant_keys)
  end

  def new(conn, _params) do
    changeset = Accounts.change_tenant_key(%TenantKey{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(%{assigns: %{tenant: tenant}} = conn, %{"tenant_key" => tenant_key_params}) do
    case Accounts.create_tenant_key(tenant_key_params |> Enum.into(%{"tenant_id" => tenant.id})) do
      {:ok, tenant_key} ->
        conn
        |> put_flash(:info, "Tenant keys created successfully.")
        |> redirect(to: tenant_path(conn, :edit, tenant))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end

  def show(%{assigns: %{tenant: tenant}} = conn, %{"id" => id}) do
    {:ok, tenant_key} = Accounts.get_tenant_key(tenant, id)
    render(conn, "show.html", tenant_key: tenant_key)
  end

  def edit(%{assigns: %{tenant: tenant}} = conn, %{"id" => id}) do
    {:ok, tenant_key} = Accounts.get_tenant_key(tenant, id)
    changeset = Accounts.change_tenant_key(tenant_key)
    render(conn, "edit.html", tenant_key: tenant_key, changeset: changeset)
  end

  def update(%{assigns: %{tenant: tenant}} = conn, %{
        "id" => id,
        "tenant_key" => tenant_key_params
      }) do
    {:ok, tenant_key} = Accounts.get_tenant_key(tenant, id)

    case Accounts.update_tenant_key(
           tenant_key,
           tenant_key_params
         ) do
      {:ok, tenant_key} ->
        conn
        |> put_flash(:info, "Tenant Key updated successfully.")
        |> redirect(to: tenant_path(conn, :edit, tenant))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html", tenant_key: tenant_key, changeset: changeset)
    end
  end

  def delete(%{assigns: %{tenant: tenant}} = conn, %{"id" => id}) do
    {:ok, tenant_key} = Accounts.get_tenant_key(tenant, id)
    {:ok, _tenant_key} = Accounts.delete_tenant_key(tenant_key)

    conn
    |> put_flash(:info, "Tenant Key deleted successfully.")
    |> redirect(to: tenant_path(conn, :edit, tenant))
  end
end
