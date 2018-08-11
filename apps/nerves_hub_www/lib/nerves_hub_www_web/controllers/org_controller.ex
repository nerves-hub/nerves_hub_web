defmodule NervesHubWWWWeb.OrgController do
  use NervesHubWWWWeb, :controller

  alias Ecto.Changeset
  alias NervesHubWWW.Accounts.Email
  alias NervesHubCore.Accounts
  alias NervesHubCore.Accounts.{Invite, OrgKey}
  alias NervesHubWWW.Mailer

  def edit(%{assigns: %{org: %{id: _conn_id} = org}} = conn, _params) do
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
      {:ok, _org} ->
        conn
        |> put_flash(:info, "Org Updated")
        |> redirect(to: org_path(conn, :edit, org))

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
    invite_params
    |> Accounts.invite(org)
    |> case do
      {:ok, invite} ->
        Email.invite(invite, org)
        |> Mailer.deliver_later()

        {:ok, invite}

        conn
        |> put_flash(:info, "User has been invited")
        |> redirect(to: org_path(conn, :edit, org))

      {:error, changeset} ->
        render(conn, "invite.html", changeset: changeset)
    end
  end
end
