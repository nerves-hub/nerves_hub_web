defmodule NervesHubWWWWeb.OrgController do
  use NervesHubWWWWeb, :controller

  alias Ecto.Changeset
  alias NervesHubWWW.Accounts.Email
  alias NervesHubWebCore.Accounts
  alias NervesHubWebCore.Accounts.{Invite, OrgKey, OrgUser}
  alias NervesHubWWW.Mailer

  plug(:validate_role, [org: :admin] when action in [:edit, :update, :invite])

  def new(conn, _params) do
    changeset = Accounts.Org.creation_changeset(%Accounts.Org{}, %{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(%{assigns: %{user: user}} = conn, %{"org" => org_params}) do
    params = org_params |> whitelist([:name])

    with {:ok, org} <- Accounts.create_org(user, params) do
      conn
      |> put_flash(:info, "Organization created successfully.")
      |> redirect(to: product_path(conn, :index, org.name))
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end

  def edit(%{assigns: %{org: org, current_limit: limits}} = conn, _params) do
    render(
      conn,
      "edit.html",
      org_changeset: %Changeset{data: org},
      org_key_changeset: %Changeset{data: %OrgKey{}},
      org: org,
      org_limit: limits
    )
  end

  def update(%{assigns: %{org: org, current_limit: limits}} = conn, %{"org" => org_params}) do
    org
    |> Accounts.update_org(org_params)
    |> case do
      {:ok, org} ->
        conn
        |> put_flash(:info, "Organization Updated")
        |> redirect(to: org_path(conn, :edit, org.name))

      {:error, changeset} ->
        render(
          conn,
          "edit.html",
          org_changeset: changeset,
          org_key_changeset: %Changeset{data: %OrgKey{}},
          org: org,
          org_limit: limits
        )
    end
  end

  def invite(%{assigns: %{org: org}} = conn, _params) do
    render(conn, "invite.html", changeset: %Changeset{data: %Invite{}}, org: org)
  end

  def send_invite(%{assigns: %{org: org}} = conn, %{"invite" => invite_params}) do
    invite_params
    |> Accounts.add_or_invite_to_org(org)
    |> case do
      {:ok, %Invite{} = invite} ->
        Email.invite(invite, org)
        |> Mailer.deliver_later()

        conn
        |> put_flash(:info, "User has been invited")
        |> redirect(to: org_path(conn, :edit, org.name))

      {:ok, %OrgUser{}} ->
        Email.org_user_created(invite_params["email"], org)
        |> Mailer.deliver_later()

        conn
        |> put_flash(:info, "User has been added to #{org.name}")
        |> redirect(to: org_path(conn, :edit, org.name))

      {:error, changeset} ->
        render(conn, "invite.html",
          changeset: %{changeset | data: %Invite{}},
          org: org,
          email: invite_params["email"]
        )
    end
  end
end
