defmodule NervesHubWeb.AccountController do
  use NervesHubWeb, :controller

  alias Ecto.Changeset
  alias NervesHub.Accounts
  alias NervesHub.Accounts.SwooshEmail
  alias NervesHub.SwooshMailer

  def invite(conn, %{"token" => token} = _) do
    with {:ok, invite} <- Accounts.get_valid_invite(token),
         {:ok, org} <- Accounts.get_org(invite.org_id) do
      render(
        conn,
        "invite.html",
        changeset: %Changeset{data: invite},
        org: org,
        token: token
      )
    else
      _ ->
        conn
        |> put_flash(:error, "Invalid or expired invite")
        |> redirect(to: "/")
    end
  end

  def accept_invite(conn, %{"user" => user_params, "token" => token} = _) do
    with {:ok, invite} <- Accounts.get_valid_invite(token),
         {:ok, org} <- Accounts.get_org(invite.org_id) do
      _accept_invite(conn, token, user_params, invite, org)
    else
      {:error, :invite_not_found} ->
        conn
        |> put_flash(:error, "Invalid or expired invite")
        |> redirect(to: "/")

      {:error, :org_not_found} ->
        conn
        |> put_flash(:error, "Invalid org")
        |> redirect(to: "/")
    end
  end

  defp _accept_invite(conn, token, user_params, invite, org) do
    with {:ok, new_org_user} <- Accounts.create_user_from_invite(invite, org, user_params) do
      # Now let everyone in the organization - except the new guy -
      # know about this new user.
      email =
        SwooshEmail.tell_org_user_added(
          org,
          Accounts.get_org_users(org),
          invite.invited_by,
          new_org_user.user
        )

      SwooshMailer.deliver(email)

      conn
      |> put_flash(:info, "Account successfully created, login below")
      |> redirect(to: "/login")
    else
      {:error, %Changeset{} = changeset} ->
        render(
          conn,
          "invite.html",
          changeset: changeset,
          org: org,
          token: token
        )
    end
  end
end
