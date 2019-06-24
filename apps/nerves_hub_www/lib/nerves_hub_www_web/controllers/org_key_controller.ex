defmodule NervesHubWWWWeb.OrgKeyController do
  use NervesHubWWWWeb, :controller

  alias NervesHubWebCore.Accounts
  alias NervesHubWebCore.Accounts.OrgKey

  plug(:validate_role, [org: :read] when action in [:index, :show])
  plug(:validate_role, [org: :write] when action in [:new, :create, :update, :edit])
  plug(:validate_role, [org: :delete] when action in [:delete])

  def index(%{assigns: %{org: org}} = conn, _params) do
    org_keys = Accounts.list_org_keys(org)
    render(conn, "index.html", org_keys: org_keys)
  end

  def new(conn, _params) do
    changeset = Accounts.change_org_key(%OrgKey{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(%{assigns: %{org: org}} = conn, %{"org_key" => org_key_params}) do
    case Accounts.create_org_key(org_key_params |> Enum.into(%{"org_id" => org.id})) do
      {:ok, _org_key} ->
        conn
        |> put_flash(:info, "Organization key created successfully.")
        |> redirect(to: org_path(conn, :edit, org.name))

      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_flash(:error, "Failed to create key -- it must have a unique name and value")
        |> redirect(to: org_path(conn, :edit, org.name))
    end
  end

  def show(%{assigns: %{org: org}} = conn, %{"id" => id}) do
    org_key = Accounts.get_org_key!(org, id)
    render(conn, "show.html", org_key: org_key)
  end

  def edit(%{assigns: %{org: org}} = conn, %{"id" => id}) do
    {:ok, org_key} = Accounts.get_org_key(org, id)
    changeset = Accounts.change_org_key(org_key)
    render(conn, "edit.html", org_key: org_key, changeset: changeset)
  end

  def update(%{assigns: %{org: org}} = conn, %{
        "id" => id,
        "org_key" => org_key_params
      }) do
    {:ok, org_key} = Accounts.get_org_key(org, id)

    case Accounts.update_org_key(
           org_key,
           org_key_params
         ) do
      {:ok, _org_key} ->
        conn
        |> put_flash(:info, "Organization key updated successfully.")
        |> redirect(to: org_path(conn, :edit, org.name))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html", org_key: org_key, changeset: changeset)
    end
  end

  def delete(%{assigns: %{org: org}} = conn, %{"id" => id}) do
    {:ok, org_key} = Accounts.get_org_key(org, id)

    with {:ok, _org_key} <- Accounts.delete_org_key(org_key) do
      conn
      |> put_flash(:info, "Organization key deleted successfully.")
      |> redirect(to: org_path(conn, :edit, org.name))
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html", org_key: org_key, changeset: changeset)
    end
  end
end
