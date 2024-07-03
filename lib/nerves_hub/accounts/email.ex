defmodule NervesHub.Accounts.SwooshEmail do
  use Phoenix.Swoosh, view: NervesHub.EmailView, layout: {NervesHub.EmailView, :layout}

  def invite(invite, org, invited_by) do
    platform_name = Application.get_env(:nerves_hub, :support_email_platform_name)

    new()
    |> from(from_address())
    |> to(invite.email)
    |> subject("Hi from #{platform_name}!")
    |> render_body("invite.html", %{invite: invite, org: org, invited_by: invited_by})
  end

  def forgot_password(%{password_reset_token: token} = user) when is_binary(token) do
    new()
    |> from(from_address())
    |> to(user.email)
    |> subject("Reset your password")
    |> render_body("forgot_password.html", user: user)
  end

  def org_user_created(email, org, invited_by) do
    new()
    |> from(from_address())
    |> to(email)
    |> subject("Welcome to #{org.name}")
    |> render_body("org_user_created.html", org: org, invited_by: invited_by)
  end

  @doc """
  Create an email that announces the addition of a new user. The email is sent
  to each of the organization's users - except the new user. The email addresses
  are specified via BCC. The instigator is the user who initiated the addition of the user.
  """
  def tell_org_user_added(org, org_users, instigator, new_user) do
    org_users_emails =
      org_users
      |> generate_org_users_emails()
      |> Enum.filter(fn email ->
        email != new_user.email
      end)

    email_subject = "#{instigator.name} added #{new_user.name} to #{org.name}"

    new()
    |> from(from_address())
    |> subject(email_subject)
    |> to(from_address())
    |> bcc(org_users_emails)
    |> render_body("tell_org_user_added.html", user: new_user, org: org, invited_by: instigator)
  end

  @doc """
  Create an email that announces the removal of a user. The email is
  sent to all of the the organization's users. The email addresses are specified via BCC.
  The instigator is the user who initiated the removal of the user.
  """
  def tell_org_user_removed(org, org_users, instigator, user_removed) do
    org_users_emails = generate_org_users_emails(org_users)

    new()
    |> from(from_address())
    |> subject("#{instigator.name} removed #{user_removed.name} from #{org.name}")
    |> to(from_address())
    |> bcc(org_users_emails)
    |> render_body("tell_org_user_removed.html", %{
      instigator: instigator,
      user: user_removed,
      org: org
    })
  end

  defp generate_org_users_emails(org_users) do
    # NB:Note there is a check for nil email addresses. This can
    # occur during testing and, in any event, causes the Bamboo emailer to crash
    Enum.reduce(org_users, [], fn %{user: %{email: email}}, acc when email != nil ->
      [email | acc]
    end)
  end

  defp from_address() do
    email = Application.fetch_env!(:nerves_hub, :from_email)
    sender = Application.fetch_env!(:nerves_hub, :email_sender)
    {sender, email}
  end
end
