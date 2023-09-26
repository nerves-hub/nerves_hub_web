defmodule NervesHubWeb.OrgController do
  use NervesHubWeb, :controller

  alias Ecto.Changeset
  alias NervesHub.Accounts
  alias NervesHub.Accounts.Email
  alias NervesHub.Accounts.{Invite, OrgKey, OrgUser}
  alias NervesHub.Mailer

  plug(:validate_role, [org: :admin] when action in [:edit, :update, :invite, :delete_invite])

  def index(conn, _params) do
    render(conn, "index.html")
  end

  def new(conn, _params) do
    changeset = Accounts.Org.creation_changeset(%Accounts.Org{}, %{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(%{assigns: %{user: user}} = conn, %{"org" => org_params}) do
    params = org_params |> whitelist([:name])

    with {:ok, org} <- Accounts.create_org(user, params) do
      conn
      |> put_flash(:info, "Organization created successfully.")
      |> redirect(to: Routes.product_path(conn, :index, org.name))
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end

  def edit(%{assigns: %{org: org}} = conn, _params) do
    render(
      conn,
      "edit.html",
      org_changeset: %Changeset{data: org},
      org_key_changeset: %Changeset{data: %OrgKey{}},
      org: org
    )
  end

  def update(%{assigns: %{org: org}} = conn, %{"org" => org_params}) do
    org
    |> Accounts.update_org(org_params)
    |> case do
      {:ok, org} ->
        conn
        |> put_flash(:info, "Organization Updated")
        |> redirect(to: Routes.org_path(conn, :edit, org.name))

      {:error, changeset} ->
        render(
          conn,
          "edit.html",
          org_changeset: changeset,
          org_key_changeset: %Changeset{data: %OrgKey{}},
          org: org
        )
    end
  end

  def invite(%{assigns: %{org: org}} = conn, _params) do
    render(conn, "invite.html", changeset: %Changeset{data: %Invite{}}, org: org)
  end

  def send_invite(%{assigns: %{org: org}} = conn, %{"invite" => invite_params}) do
    case Accounts.add_or_invite_to_org(invite_params, org) do
      {:ok, %Invite{} = invite} ->
        Email.invite(invite, org)
        |> Mailer.deliver_later()

        conn
        |> put_flash(:info, "User has been invited")
        |> redirect(to: Routes.org_user_path(conn, :index, conn.assigns.org.name))

      {:ok, %OrgUser{}} ->
        Email.org_user_created(invite_params["email"], org)
        |> Mailer.deliver_later()

        conn
        |> put_flash(:info, "User has been added to #{org.name}")
        |> redirect(to: Routes.org_user_path(conn, :index, conn.assigns.org.name))

      {:error, changeset} ->
        render(conn, "invite.html",
          changeset: %{changeset | data: %Invite{}},
          org: org,
          email: invite_params["email"]
        )
    end
  end

  def delete_invite(%{assigns: %{org: org}} = conn, %{"token" => token}) do
    case Accounts.delete_invite(org, token) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Invite rescinded")
        |> redirect(to: Routes.org_user_path(conn, :index, org.name))

      {:error, _} ->
        conn
        |> put_flash(:error, "Invite failed to rescind")
        |> redirect(to: Routes.org_user_path(conn, :index, org.name))
    end
  end
end
