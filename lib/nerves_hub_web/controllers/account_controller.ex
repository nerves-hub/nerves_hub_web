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

  @doc """
  The invite landing page.

  What the invitee is shown depends on who (if anyone) they are signed in as:

    * signed in as the invited email - accept or decline the invite
    * signed in as somebody else - told which account the invite is for
    * signed out with an existing account - asked to sign in first
    * signed out without an account - registration form
  """
  def invite(conn, %{"token" => token}) do
    with {:ok, invite} <- Accounts.get_valid_invite(token),
         {:ok, org} <- Accounts.get_org(invite.org_id) do
      conn
      |> assign(:changeset, %Changeset{data: invite})
      |> assign(:invite, invite)
      |> assign(:org, org)
      |> assign(:token, token)
      |> render_invite(invite, token)
    else
      _ ->
        conn
        |> put_flash(:error, "Invalid or expired invite")
        |> redirect(to: "/login")
    end
  end

  defp render_invite(conn, invite, token) do
    case current_user(conn) do
      %User{} = user ->
        if Accounts.invite_addressed_to?(invite, user) do
          render(conn, :invite, mode: :accept)
        else
          render(conn, :invite, mode: :wrong_account)
        end

      nil ->
        mode =
          case Accounts.get_user_by_email(invite.email) do
            {:ok, _user} -> :sign_in
            {:error, :not_found} -> :register
          end

        conn
        # so signing in (or signing up with an OAuth provider) returns the
        # invitee to this page, where they can accept
        |> put_session(:login_redirect_path, ~p"/invite/#{token}")
        |> render(:invite, mode: mode)
    end
  end

  @doc """
  Accepts an invite for someone who already has an account.
  """
  def accept_invite(conn, %{"token" => token}) do
    with %User{} = user <- current_user(conn),
         {:ok, invite} <- Accounts.get_valid_invite(token),
         {:ok, org} <- Accounts.get_org(invite.org_id),
         {:ok, org_user} <- Accounts.accept_invite(invite, user) do
      _ = UserNotifier.deliver_all_tell_org_user_added(org, invite.invited_by, org_user.user)

      conn
      |> put_flash(:info, "Welcome to #{org.name}!")
      |> redirect(to: ~p"/org/#{org}")
    else
      nil ->
        conn
        |> put_flash(:error, "Please sign in to accept this invite")
        |> redirect(to: ~p"/invite/#{token}")

      {:error, :email_mismatch} ->
        conn
        |> put_flash(:error, "This invite was sent to a different email address")
        |> redirect(to: ~p"/invite/#{token}")

      _ ->
        conn
        |> put_flash(:error, "Invalid or expired invite")
        |> redirect(to: "/")
    end
  end

  @doc """
  Declines an invite, whether or not the invitee has an account.
  """
  def decline_invite(conn, %{"token" => token}) do
    with {:ok, invite} <- Accounts.get_valid_invite(token),
         {:ok, _invite} <- Accounts.decline_invite(invite) do
      conn
      |> delete_session(:login_redirect_path)
      |> put_flash(:info, "Invitation declined")
      |> redirect(to: declined_redirect(conn))
    else
      _ ->
        conn
        |> put_flash(:error, "Invalid or expired invite")
        |> redirect(to: "/")
    end
  end

  @doc """
  Registers an account for an invitee who doesn't have one yet, and joins them
  to the inviting org.
  """
  def register_from_invite(conn, %{"user" => user_params, "token" => token}) do
    with nil <- current_user(conn),
         {:ok, invite} <- Accounts.get_valid_invite(token),
         {:ok, org} <- Accounts.get_org(invite.org_id) do
      _register_from_invite(conn, token, user_params, invite, org)
    else
      %User{} ->
        # already signed in, so accepting is all that's left to do
        redirect(conn, to: ~p"/invite/#{token}")

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

  defp _register_from_invite(conn, token, user_params, invite, org) do
    case Accounts.create_user_from_invite(invite, org, user_params) do
      {:ok, new_org_user} ->
        # Now let all admins in the organization know about this new user.
        _ =
          UserNotifier.deliver_all_tell_org_user_added(org, invite.invited_by, new_org_user.user)

        conn
        # the invite has been accepted, so don't bounce them back to it
        |> delete_session(:login_redirect_path)
        |> put_flash(:info, "Welcome to NervesHub!")
        |> Auth.log_in_user(new_org_user.user, user_params)

      {:error, %Changeset{} = changeset} ->
        conn
        |> assign(:changeset, changeset)
        |> assign(:invite, invite)
        |> assign(:org, org)
        |> assign(:token, token)
        |> render(:invite, mode: :register)
    end
  end

  defp current_user(conn), do: conn.assigns.current_scope && conn.assigns.current_scope.user

  defp declined_redirect(conn) do
    if current_user(conn), do: ~p"/orgs", else: ~p"/login"
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
