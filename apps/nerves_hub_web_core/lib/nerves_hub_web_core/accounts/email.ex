defmodule NervesHubWebCore.Accounts.Email do
  use Bamboo.Phoenix, view: NervesHubWebCore.EmailView

  alias NervesHubWebCore.Accounts.{Invite, Org, User, OrgUser}

  @from {"NervesHub", "no-reply@nerves-hub.org"}

  def invite(%Invite{} = invite, %Org{} = org) do
    new_email()
    |> from(@from)
    |> to(invite.email)
    |> subject("[NervesHub] Hi from NervesHub!")
    |> put_layout({NervesHubWebCore.EmailView, :layout})
    |> render("invite.html", invite: invite, org: org)
  end

  def forgot_password(%User{email: email, password_reset_token: token} = user)
      when is_binary(token) do
    new_email()
    |> from(@from)
    |> to(email)
    |> subject("[NervesHub] Reset NervesHub Password")
    |> put_layout({NervesHubWebCore.EmailView, :layout})
    |> render("forgot_password.html", user: user)
  end

  def org_user_created(email, %Org{} = org) do
    new_email()
    |> from(@from)
    |> to(email)
    |> subject("[NervesHub] Welcome to #{org.name}")
    |> put_layout({NervesHubWebCore.EmailView, :layout})
    |> render("org_user_created.html", org: org)
  end

  @doc """
  Create an email that announces the addition of a new user. The email is sent
  to each of the organization's users - except the new user. The email addresses
  are specified via BCC. The instigator is the user who initiated the addition of the user.
  """
  def tell_org_user_added(%Org{} = org, org_users, instigator, %User{} = new_user) do
    org_users_emails =
      generate_org_users_emails(org_users)
      |> Enum.filter(fn email -> email != new_user.email end)

    new_email()
    |> from(@from)
    |> subject("[NervesHub] User #{instigator} added #{new_user.username} to #{org.name}")
    |> to(@from)
    |> bcc(org_users_emails)
    |> put_layout({NervesHubWebCore.EmailView, :layout})
    |> render("tell_org_user_added.html", instigator: instigator, user: new_user, org: org)
  end

  @doc """
  Create an email that announces the removal of a user. The email is
  sent to all of the the organization's users. The email addresses are specified via BCC.
  The instigator is the user who initiated the removal of the user.
  """
  def tell_org_user_removed(%Org{} = org, org_users, instigator, %User{} = user_removed) do
    org_users_emails = generate_org_users_emails(org_users)

    new_email()
    |> from(@from)
    |> subject("[NervesHub] User #{instigator} removed #{user_removed.username} from #{org.name}")
    |> to(@from)
    |> bcc(org_users_emails)
    |> put_layout({NervesHubWebCore.EmailView, :layout})
    |> render("tell_org_user_removed.html", instigator: instigator, user: user_removed, org: org)
  end

  defp generate_org_users_emails(org_users) do
    # NB:Note there is a check for nil email addresses. This can
    # occur during testing and, in any event, causes the Bamboo emailer to crash
    org_users
    |> Enum.reduce(
      [],
      fn %OrgUser{user: %User{email: email}}, acc when email != nil ->
        [email | acc]
      end
    )
  end
end
