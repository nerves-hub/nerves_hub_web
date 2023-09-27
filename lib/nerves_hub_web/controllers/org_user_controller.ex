defmodule NervesHubWeb.OrgUserController do
  use NervesHubWeb, :controller

  alias NervesHub.Accounts
  alias NervesHub.Accounts.SwooshEmail
  alias NervesHub.Accounts.Org
  alias NervesHub.SwooshMailer

  plug(NervesHubWeb.Plugs.OrgUser when action in [:delete, :edit, :update])
  plug(:validate_role, org: :admin)

  def index(%{assigns: %{org: org}} = conn, _params) do
    conn
    |> render(
      "index.html",
      org_users: Accounts.get_org_users(org),
      invites: Accounts.get_invites_for_org(org),
      org: org
    )
  end

  def edit(%{assigns: %{org_user: org_user}} = conn, _params) do
    conn
    |> render("edit.html",
      changeset: Org.change_user_role(org_user, %{})
    )
  end

  def update(%{assigns: %{org: org, org_user: org_user}} = conn, %{"org_user" => params}) do
    {:ok, role} = Map.fetch(params, "role")

    with {:ok, _org_user} <- Accounts.change_org_user_role(org_user, role) do
      conn
      |> put_flash(:info, "Role updated")
      |> redirect(to: Routes.org_user_path(conn, :index, org.name))
    else
      {:error, changeset} ->
        conn
        |> put_flash(:error, "Error updating role")
        |> render(
          "edit.html",
          changeset: changeset
        )
    end
  end

  def delete(%{assigns: %{org: org, org_user: org_user, user: current_user}} = conn, _params) do
    case Accounts.remove_org_user(org, org_user.user) do
      :ok ->
        instigator = current_user.username

        SwooshEmail.tell_org_user_removed(
          org,
          Accounts.get_org_users(org),
          instigator,
          org_user.user
        )
        |> SwooshMailer.deliver()

        conn
        |> put_flash(:info, "User removed")
        |> redirect(to: Routes.org_user_path(conn, :index, org.name))

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not remove user")
        |> redirect(to: Routes.org_user_path(conn, :index, org.name))
    end
  end
end
