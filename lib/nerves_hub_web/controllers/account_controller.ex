defmodule NervesHubWeb.AccountController do
  use NervesHubWeb, :controller

  alias Ecto.Changeset
  alias NervesHub.Accounts
  alias NervesHub.Accounts.{User, SwooshEmail}
  alias NervesHub.SwooshMailer

  import Phoenix.HTML.Link

  plug(:registrations_allowed when action in [:new, :create])

  def new(conn, _params) do
    render(conn, "new.html", changeset: Ecto.Changeset.change(%User{}))
  end

  def delete(conn, %{"user_name" => username}) do
    with {:ok, user} <- Accounts.get_user_by_username(username),
         {:ok, _} <- Accounts.remove_account(user.id) do
      conn
      |> put_flash(:info, "Success")
      |> redirect(to: "/login")
    end
  end

  def update(conn, params) do
    cleaned =
      params["user"]
      |> whitelist([:current_password, :password, :username, :email, :orgs])

    conn.assigns.user
    |> Accounts.update_user(cleaned)
    |> case do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Account successfully created, login below")
        |> redirect(to: "/login")

      {:error, %Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end

  def invite(conn, %{"token" => token} = _) do
    with {:ok, invite} <- Accounts.get_valid_invite(token),
         {:ok, org} <- Accounts.get_org(invite.org_id) do
      # QUESTION: Should this be here raw or in a method somewhere else?
      case Map.has_key?(conn.assigns, :user) && !is_nil(conn.assigns.user) do
        true ->
          if invite.email == conn.assigns.user.email do
            render(
              conn,
              # QUESTION: Should this be a separate template or the same one with conditional rendering?
              "invite_existing.html",
              changeset: %Changeset{data: invite},
              org: org,
              token: token
            )
          else
            conn
            |> put_flash(:error, "Invite not intended for the current user")
            |> redirect(to: "/")
          end

        false ->
          case Accounts.get_user_by_email(invite.email) do
            # Invites for existing users
            {:ok, _recipient} ->
              conn
              |> put_flash(:error, "You must be logged in to accept this invite")
              |> redirect(to: "/login")

            # Invites for new users
            {:error, :not_found} ->
              render(
                conn,
                "invite.html",
                changeset: %Changeset{data: invite},
                org: org,
                token: token
              )
          end
      end
    else
      _ ->
        conn
        |> put_flash(:error, "Invalid or expired invite")
        |> redirect(to: "/")
    end
  end

  def accept_invite(conn, %{"user" => user_params, "token" => token} = _) do
    clean_params = whitelist(user_params, [:password, :username])

    with {:ok, invite} <- Accounts.get_valid_invite(token),
         {:ok, org} <- Accounts.get_org(invite.org_id) do
      _accept_invite(conn, token, clean_params, invite, org)
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

  def maybe_show_invites(conn) do
    case Map.has_key?(conn.assigns, :user) && !is_nil(conn.assigns.user) do
      true ->
        case conn.assigns.user
             |> Accounts.get_invites_for_user() do
          [] ->
            conn

          invites ->
            conn
            |> put_flash(
              :info,
              [
                "You have " <>
                  (length(invites) |> Integer.to_string()) <>
                  " pending invite" <>
                  if(length(invites) > 1, do: "s", else: "") <> " to organizations. ",
                  link("Click here to view pending invites.",
                  to: "/org/" <> conn.assigns.user.username <> "/invites"
                )
              ]
            )
        end

      false ->
        conn
      end
    end
end
