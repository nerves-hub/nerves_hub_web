defmodule NervesHubWeb.AccountController do
  use NervesHubWeb, :controller

  alias Ecto.Changeset
  alias NervesHub.Accounts
  alias NervesHub.Accounts.User
  alias NervesHub.Accounts.UserNotifier

  alias NervesHubWeb.Auth

  plug(:registrations_allowed when action in [:new, :create])

  def new(conn, _params) do
    changeset = Ecto.Changeset.change(%User{})

    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.create_user(user_params) do
      {:ok, new_user} ->
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            new_user,
            &url(~p"/confirm/#{&1}")
          )

        conn
        |> assign(:email, new_user.email)
        |> render(:registered)

      {:error, %Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  def invite(conn, %{"token" => token}) do
    with {:ok, invite} <- Accounts.get_valid_invite(token),
         {:ok, org} <- Accounts.get_org(invite.org_id) do
      conn
      |> assign(:changeset, %Changeset{data: invite})
      |> assign(:org, org)
      |> assign(:token, token)
      |> render(:invite)
    else
      _ ->
        conn
        |> put_flash(:error, "Invalid or expired invite")
        |> redirect(to: "/login")
    end
  end

  def accept_invite(conn, %{"token" => token, "user" => user_params}) do
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
    case Accounts.create_user_from_invite(invite, org, user_params) do
      {:ok, new_org_user} ->
        # Now let all admins in the organization know about this new user.
        _ =
          UserNotifier.deliver_all_tell_org_user_added(org, invite.invited_by, new_org_user.user)

        conn
        |> put_flash(:info, "Welcome to NervesHub!")
        |> Auth.log_in_user(new_org_user.user, user_params)

      {:error, %Changeset{} = changeset} ->
        conn
        |> assign(:changeset, changeset)
        |> assign(:org, org)
        |> assign(:token, token)
        |> render(:invite)
    end
  end

  defp registrations_allowed(conn, _options) do
    if Application.get_env(:nerves_hub, :open_for_registrations) do
      conn
    else
      conn
      |> put_flash(:info, "Please contact support for an invite to this platform.")
      |> redirect(to: "/login")
      |> halt()
    end
  end
end
