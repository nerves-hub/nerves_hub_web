defmodule NervesHub.Accounts.UserNotifier do
  import Swoosh.Email

  alias NervesHub.Accounts
  alias NervesHub.Accounts.User

  alias NervesHub.Emails.ConfirmationTemplate
  alias NervesHub.Emails.LoginWithGoogleReminderTemplate
  alias NervesHub.Emails.OrgUserAddedTemplate
  alias NervesHub.Emails.PasswordResetTemplate
  alias NervesHub.Emails.PasswordResetConfirmationTemplate
  alias NervesHub.Emails.PasswordUpdatedTemplate
  alias NervesHub.Emails.TellOrgUserAddedTemplate
  alias NervesHub.Emails.TellOrgUserInvitedTemplate
  alias NervesHub.Emails.TellOrgUserRemovedTemplate
  alias NervesHub.Emails.UserInviteTemplate
  alias NervesHub.Emails.WelcomeTemplate

  alias NervesHub.SwooshMailer, as: Mailer

  def deliver_confirmation_instructions(user, confirmation_url) do
    assigns = %{
      user_name: user.name,
      confirmation_url: confirmation_url,
      platform_name: platform_name()
    }

    html = ConfirmationTemplate.render(assigns)
    text = ConfirmationTemplate.text_render(assigns)

    send_email(user, "#{platform_name()}: Confirm your account", html, text)
  end

  def deliver_password_updated(user, reset_url) do
    assigns = %{
      user_name: user.name,
      reset_url: reset_url,
      platform_name: platform_name()
    }

    html = PasswordUpdatedTemplate.render(assigns)
    text = PasswordUpdatedTemplate.text_render(assigns)

    send_email(user, "#{platform_name()}: Your password has been updated", html, text)
  end

  def deliver_login_with_google_reminder(user, login_url) do
    assigns = %{
      user_name: user.name,
      login_url: login_url,
      platform_name: platform_name()
    }

    html = LoginWithGoogleReminderTemplate.render(assigns)
    text = LoginWithGoogleReminderTemplate.text_render(assigns)

    send_email(user, "#{platform_name()}: Login with Google", html, text)
  end

  def deliver_reset_password_instructions(user, reset_url) do
    assigns = %{
      user_name: user.name,
      reset_url: reset_url,
      platform_name: platform_name()
    }

    html = PasswordResetTemplate.render(assigns)
    text = PasswordResetTemplate.text_render(assigns)

    send_email(user, "#{platform_name()}: Reset your password", html, text)
  end

  def deliver_reset_password_confirmation(user) do
    assigns = %{
      user_name: user.name,
      platform_name: platform_name()
    }

    html = PasswordResetConfirmationTemplate.render(assigns)
    text = PasswordResetConfirmationTemplate.text_render(assigns)

    send_email(user, "#{platform_name()}: Your password has been reset", html, text)
  end

  def deliver_welcome_email(user) do
    assigns = %{user_name: user.name, platform_name: platform_name()}

    html = WelcomeTemplate.render(assigns)
    text = WelcomeTemplate.text_render(assigns)

    send_email(user, "#{platform_name()}: Welcome #{user.name}!", html, text)
  end

  def deliver_user_invite(email, org, invited_by, invite_url) do
    assigns = %{
      org_name: org.name,
      platform_name: platform_name(),
      invited_by_name: invited_by.name,
      invite_url: invite_url
    }

    html = UserInviteTemplate.render(assigns)
    text = UserInviteTemplate.text_render(assigns)

    send_email(
      email,
      "#{platform_name()}: You have been invited to join #{org.name}",
      html,
      text
    )
  end

  def deliver_org_user_added(org, user, invited_by) do
    assigns = %{
      user_name: user.name,
      invited_by_name: invited_by.name,
      org_name: org.name
    }

    html = OrgUserAddedTemplate.render(assigns)
    text = OrgUserAddedTemplate.text_render(assigns)

    send_email(
      user,
      "#{platform_name()}: You have been added to #{org.name}",
      html,
      text
    )
  end

  def deliver_all_tell_org_user_invited(org, instigator, new_user_email) do
    admins = Accounts.get_org_admins(org)

    for admin <- admins do
      deliver_tell_org_user_invited(org, admin, instigator, new_user_email)
    end
  end

  def deliver_tell_org_user_invited(org, admin, instigator, new_user_email) do
    assigns = %{
      user_name: admin.name,
      new_user_email: new_user_email,
      invited_by_name: instigator.name,
      org_name: org.name
    }

    html = TellOrgUserInvitedTemplate.render(assigns)
    text = TellOrgUserInvitedTemplate.text_render(assigns)

    send_email(
      admin,
      "#{platform_name()}: #{new_user_email} has been invited to #{org.name}",
      html,
      text
    )
  end

  def deliver_all_tell_org_user_added(org, instigator, new_user) do
    admins =
      Accounts.get_org_admins(org)
      |> Enum.reject(&(&1.id == instigator.id))

    Enum.map(admins, fn admin ->
      deliver_tell_org_user_added(org, admin, instigator, new_user)
    end)
  end

  def deliver_tell_org_user_added(org, admin, instigator, new_user) do
    assigns = %{
      user_name: admin.name,
      new_user_name: new_user.name,
      invited_by_name: instigator.name,
      org_name: org.name
    }

    html = TellOrgUserAddedTemplate.render(assigns)
    text = TellOrgUserAddedTemplate.text_render(assigns)

    send_email(
      admin,
      "#{platform_name()}: #{new_user.name} has been added to #{org.name}",
      html,
      text
    )
  end

  def deliver_all_tell_org_user_removed(org, instigator, user) do
    admins =
      Accounts.get_org_admins(org)
      |> Enum.reject(&(&1.id == instigator.id))

    Enum.map(admins, fn admin ->
      deliver_tell_org_user_removed(org, admin, instigator, user)
    end)
  end

  def deliver_tell_org_user_removed(org, admin, instigator, removed_user) do
    assigns = %{
      user_name: admin.name,
      removed_user_name: removed_user.name,
      instigator_name: instigator.name,
      org_name: org.name
    }

    html = TellOrgUserRemovedTemplate.render(assigns)
    text = TellOrgUserRemovedTemplate.text_render(assigns)

    send_email(
      admin,
      "#{platform_name()}: #{removed_user.name} has been removed from #{org.name}",
      html,
      text
    )
  end

  defp send_email(%User{} = user, subject, html, text) do
    send_email(user.email, subject, html, text)
  end

  defp send_email(user_email, subject, html, text) do
    email =
      new()
      |> to(user_email)
      |> from(from_address())
      |> subject(subject)
      |> html_body(html)
      |> text_body(text)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp from_address() do
    email = Application.fetch_env!(:nerves_hub, :from_email)
    sender = Application.fetch_env!(:nerves_hub, :email_sender)
    {sender, email}
  end

  defp platform_name(), do: Application.get_env(:nerves_hub, :support_email_platform_name)
end
