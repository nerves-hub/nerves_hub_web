defmodule NervesHubWWWWeb.OrgUserController do
  use NervesHubWWWWeb, :controller

  alias NervesHubWebCore.Accounts
  alias NervesHubWebCore.Accounts.{Email, Org}
  alias NervesHubWebCore.Mailer

  plug(:validate_role, org: :admin)

  def index(%{assigns: %{org: org}} = conn, _params) do
    conn
    |> render(
      "index.html",
      org_users: Accounts.get_org_users(org),
      org: org
    )
  end

  def edit(%{assigns: %{org: org}} = conn, %{"user_id" => user_id}) do
    {:ok, user} = Accounts.get_user(user_id)
    {:ok, org_user} = Accounts.get_org_user(org, user)

    conn
    |> render("edit.html",
      changeset: Org.change_user_role(org_user, %{}),
      org_user: org_user
    )
  end

  def update(%{assigns: %{org: org}} = conn, %{"user_id" => user_id} = params) do
    {:ok, user} = Accounts.get_user(user_id)
    {:ok, org_user} = Accounts.get_org_user(org, user)
    {:ok, role} = Map.fetch(params["org_user"], "role")

    case Accounts.change_org_user_role(org_user, role) do
      {:ok, _org_user} ->
        conn
        |> put_flash(:info, "Role updated")
        |> redirect(to: Routes.org_user_path(conn, :index, org.name))

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Error updating role")
        |> render(
          "edit.html",
          changeset: changeset,
          org_user: org_user
        )
    end
  end

  def delete(%{assigns: %{org: org, user: current_user}} = conn, %{"user_id" => user_id}) do
    {:ok, user} = Accounts.get_user(user_id)

    case Accounts.remove_org_user(org, user) do
      :ok ->
        instigator = current_user.username

        Email.tell_org_user_removed(org, Accounts.get_org_users(org), instigator, user)
        |> Mailer.deliver_later()

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
