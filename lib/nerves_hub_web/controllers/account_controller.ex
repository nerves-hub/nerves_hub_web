defmodule NervesHubWeb.AccountController do
  use NervesHubWeb, :controller

  alias Ecto.Changeset
  alias NervesHub.Accounts
  alias NervesHub.Accounts.SwooshEmail
  alias NervesHub.SwooshMailer

  import Phoenix.HTML.Link

  def edit(conn, _params) do
    conn
    |> render(
      "edit.html",
      changeset: %Changeset{data: conn.assigns.user}
    )
  end

  def confirm_delete(conn, _) do
    render(conn, "delete.html")
  end

  def delete(conn, %{"user_name" => username, "confirm_username" => confirmed_username})
      when username != confirmed_username do
    conn
    |> put_flash(:error, "Please type #{username} to confirm.")
    |> redirect(to: Routes.account_path(conn, :confirm_delete, username))
  end

  def delete(conn, %{"user_name" => username}) do
    with {:ok, user} <- Accounts.get_user_by_username(username),
         {:ok, _} <- Accounts.remove_account(user.id) do
      conn
      |> put_flash(:info, "Success")
      |> redirect(to: "/login")
    end
  end

  def invites(conn, params) do
    case Accounts.get_user_by_username(params["username"]) do
      {:ok, user} ->
        case Accounts.get_invites_for_user(user) do
          [] ->
            conn
            |> put_flash(:info, "No pending invites")
            |> redirect(to: Routes.account_path(conn, :edit, user.username))

          invites ->
            conn
            |> render("invites.html", invites: invites)
        end

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "User not found")
        |> redirect(to: "/")
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
        |> put_flash(:info, "Account updated")
        |> redirect(to: Routes.account_path(conn, :edit, user.username))

      {:error, changeset} ->
        conn
        |> render("edit.html", changeset: changeset)
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

  def accept_invite(conn, %{"token" => token} = params) do
    with {:ok, invite} <- Accounts.get_valid_invite(token),
         {:ok, org} <- Accounts.get_org(invite.org_id) do
      case Accounts.get_user_by_email(invite.email) do
        {:ok, _recipient} ->
          _accept_invite_existing(conn, token, invite, org)

        {:error, :not_found} ->
          clean_params =
            params
            |> Map.fetch!("user")
            |> whitelist([:password, :username])

          _accept_invite(conn, token, clean_params, invite, org)
      end
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

  defp _accept_invite(conn, token, clean_params, invite, org) do
    with {:ok, new_org_user} <- Accounts.create_user_from_invite(invite, org, clean_params) do
      # Now let everyone in the organization - except the new guy -
      # know about this new user.

      # TODO: Fix this - We don't have the instigating user in the conn
      # anymore, and the new user is not always the instigator.
      instigator =
        case conn.assigns do
          %{user: %{username: username}} -> username
          _ -> nil
        end

      email =
        SwooshEmail.tell_org_user_added(
          org,
          Accounts.get_org_users(org),
          instigator,
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

  defp _accept_invite_existing(conn, token, invite, org) do
    with {:ok, new_org_user} <- Accounts.accept_invite(invite, org) do
      # Now let everyone in the organization - except the new guy -
      # know about this new user.

      # TODO: Fix this - We don't have the instigating user in the conn
      # anymore, and the new user is not always the instigator.
      instigator =
        case conn.assigns do
          %{user: %{username: username}} -> username
          _ -> nil
        end

      email =
        SwooshEmail.tell_org_user_added(
          org,
          Accounts.get_org_users(org),
          instigator,
          new_org_user.user
        )

      SwooshMailer.deliver(email)

      conn
      |> put_flash(:info, "Organization successfully joined")
      |> redirect(to: "/")
    else
      {:error, %Changeset{} = changeset} ->
        render(
          conn,
          "invite_existing.html",
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
