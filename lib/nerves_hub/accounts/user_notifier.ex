defmodule NervesHub.Accounts.UserNotifier do
  @moduledoc """
  The emails NervesHub sends to its users.

  Every `deliver_*` function queues a `NervesHub.Workers.SendEmail` job rather
  than talking to the mail server itself, so a slow or unreachable SMTP relay
  can't stall a web request or a LiveView event. A job carries the recipient, a
  template key and that template's assigns; `render_and_deliver/3` turns those
  back into a message when the job runs.

  They return whatever `Oban.insert/1` or `Oban.insert_all/1` returned, so a
  successful call means the email is queued, not that it has been delivered.
  """

  import Swoosh.Email

  alias NervesHub.Accounts
  alias NervesHub.Accounts.User
  alias NervesHub.Emails.ConfirmationTemplate
  alias NervesHub.Emails.LoginWithGoogleReminderTemplate
  alias NervesHub.Emails.PasswordResetConfirmationTemplate
  alias NervesHub.Emails.PasswordResetTemplate
  alias NervesHub.Emails.PasswordUpdatedTemplate
  alias NervesHub.Emails.TellOrgUserAddedTemplate
  alias NervesHub.Emails.TellOrgUserInvitedTemplate
  alias NervesHub.Emails.TellOrgUserRemovedTemplate
  alias NervesHub.Emails.TellOrgUserRemovedThemselfTemplate
  alias NervesHub.Emails.UserInviteTemplate
  alias NervesHub.Emails.WelcomeTemplate
  alias NervesHub.SwooshMailer, as: Mailer
  alias NervesHub.Workers.SendEmail
  alias Phoenix.HTML.Safe

  def deliver_confirmation_instructions(user, confirmation_url) do
    Oban.insert(
      job("confirmation", user, %{
        user_name: user.name,
        confirmation_url: confirmation_url
      })
    )
  end

  def deliver_password_updated(user, reset_url) do
    Oban.insert(job("password_updated", user, %{user_name: user.name, reset_url: reset_url}))
  end

  def deliver_login_with_google_reminder(user, login_url) do
    Oban.insert(job("login_with_google_reminder", user, %{user_name: user.name, login_url: login_url}))
  end

  def deliver_reset_password_instructions(user, reset_url) do
    Oban.insert(job("password_reset", user, %{user_name: user.name, reset_url: reset_url}))
  end

  def deliver_reset_password_confirmation(user) do
    Oban.insert(job("password_reset_confirmation", user, %{user_name: user.name}))
  end

  def deliver_welcome_email(user) do
    Oban.insert(job("welcome", user, %{user_name: user.name}))
  end

  @doc """
  Emails an invitee the link they use to accept an org invitation.

  `has_account?` tells the invitee whether they'll be signing in or registering
  when they follow the link.
  """
  def deliver_user_invite(email, org, invited_by, invite_url, has_account?) do
    Oban.insert(
      job("user_invite", email, %{
        org_name: org.name,
        invited_by_name: invited_by.name,
        invite_url: invite_url,
        has_account: has_account?
      })
    )
  end

  def deliver_all_tell_org_user_invited(org, instigator, new_user_email) do
    org
    |> Accounts.get_org_admins()
    |> Enum.map(&tell_org_user_invited_job(org, &1, instigator, new_user_email))
    |> Oban.insert_all()
  end

  def deliver_tell_org_user_invited(org, admin, instigator, new_user_email) do
    org
    |> tell_org_user_invited_job(admin, instigator, new_user_email)
    |> Oban.insert()
  end

  def deliver_all_tell_org_user_added(org, instigator, new_user) do
    org
    |> Accounts.get_org_admins()
    |> Enum.reject(&(&1.id == instigator.id))
    |> Enum.map(&tell_org_user_added_job(org, &1, instigator, new_user))
    |> Oban.insert_all()
  end

  def deliver_tell_org_user_added(org, admin, instigator, new_user) do
    org
    |> tell_org_user_added_job(admin, instigator, new_user)
    |> Oban.insert()
  end

  def deliver_all_tell_org_user_removed(org, instigator, user) do
    org
    |> Accounts.get_org_admins()
    |> Enum.reject(&(&1.id == instigator.id))
    |> Enum.map(&tell_org_user_removed_job(org, &1, instigator, user))
    |> Oban.insert_all()
  end

  def deliver_tell_org_user_removed(org, admin, instigator, removed_user) do
    org
    |> tell_org_user_removed_job(admin, instigator, removed_user)
    |> Oban.insert()
  end

  def deliver_all_tell_org_user_removed_themself(org, user) do
    org
    |> Accounts.get_org_admins()
    |> Enum.map(&tell_org_user_removed_themself_job(org, &1, user))
    |> Oban.insert_all()
  end

  def deliver_tell_org_user_removed_themself(org, admin, removed_user) do
    org
    |> tell_org_user_removed_themself_job(admin, removed_user)
    |> Oban.insert()
  end

  @doc """
  Renders and delivers one email.

  Called by `NervesHub.Workers.SendEmail` when a job runs. To send an email use
  one of the `deliver_*` functions, which queue the job that lands here.
  """
  @spec render_and_deliver(String.t(), String.t(), map()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def render_and_deliver(template, recipient, assigns) do
    assigns =
      assigns
      |> atomize_keys()
      |> Map.put(:platform_name, platform_name())

    {html, text} = render(template_module(template), assigns)

    email =
      new()
      |> to(recipient)
      |> from(from_address())
      |> subject(subject_for(template, assigns))
      |> html_body(html)
      |> text_body(text)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp tell_org_user_invited_job(org, admin, instigator, new_user_email) do
    job("tell_org_user_invited", admin, %{
      user_name: admin.name,
      new_user_email: new_user_email,
      invited_by_name: instigator.name,
      org_name: org.name
    })
  end

  defp tell_org_user_added_job(org, admin, instigator, new_user) do
    job("tell_org_user_added", admin, %{
      user_name: admin.name,
      new_user_name: new_user.name,
      invited_by_name: instigator.name,
      org_name: org.name
    })
  end

  defp tell_org_user_removed_job(org, admin, instigator, removed_user) do
    job("tell_org_user_removed", admin, %{
      user_name: admin.name,
      removed_user_name: removed_user.name,
      instigator_name: instigator.name,
      org_name: org.name
    })
  end

  defp tell_org_user_removed_themself_job(org, admin, removed_user) do
    job("tell_org_user_removed_themself", admin, %{
      user_name: admin.name,
      removed_user_name: removed_user.name,
      org_name: org.name
    })
  end

  defp job(template, %User{} = user, assigns), do: job(template, user.email, assigns)

  defp job(template, recipient, assigns) when is_binary(recipient) do
    SendEmail.new(%{template: template, to: recipient, assigns: assigns})
  end

  defp template_module("confirmation"), do: ConfirmationTemplate
  defp template_module("login_with_google_reminder"), do: LoginWithGoogleReminderTemplate
  defp template_module("password_reset"), do: PasswordResetTemplate
  defp template_module("password_reset_confirmation"), do: PasswordResetConfirmationTemplate
  defp template_module("password_updated"), do: PasswordUpdatedTemplate
  defp template_module("tell_org_user_added"), do: TellOrgUserAddedTemplate
  defp template_module("tell_org_user_invited"), do: TellOrgUserInvitedTemplate
  defp template_module("tell_org_user_removed"), do: TellOrgUserRemovedTemplate
  defp template_module("tell_org_user_removed_themself"), do: TellOrgUserRemovedThemselfTemplate
  defp template_module("user_invite"), do: UserInviteTemplate
  defp template_module("welcome"), do: WelcomeTemplate

  defp subject_for("confirmation", _assigns), do: "#{platform_name()}: Confirm your account"

  defp subject_for("login_with_google_reminder", _assigns), do: "#{platform_name()}: Login with Google"

  defp subject_for("password_reset", _assigns), do: "#{platform_name()}: Reset your password"

  defp subject_for("password_reset_confirmation", _assigns), do: "#{platform_name()}: Your password has been reset"

  defp subject_for("password_updated", _assigns), do: "#{platform_name()}: Your password has been updated"

  defp subject_for("tell_org_user_added", %{new_user_name: new_user_name, org_name: org_name}),
    do: "#{platform_name()}: #{new_user_name} has been added to #{org_name}"

  defp subject_for("tell_org_user_invited", %{new_user_email: new_user_email, org_name: org_name}),
    do: "#{platform_name()}: #{new_user_email} has been invited to #{org_name}"

  defp subject_for("tell_org_user_removed", %{removed_user_name: removed_user_name, org_name: org_name}),
    do: "#{platform_name()}: #{removed_user_name} has been removed from #{org_name}"

  defp subject_for("tell_org_user_removed_themself", %{removed_user_name: removed_user_name, org_name: org_name}),
    do: "#{platform_name()}: #{removed_user_name} has been removed from #{org_name}"

  defp subject_for("user_invite", %{org_name: org_name}),
    do: "#{platform_name()}: You have been invited to join #{org_name}"

  defp subject_for("welcome", %{user_name: user_name}), do: "#{platform_name()}: Welcome #{user_name}!"

  defp render(module, assigns) do
    html = module.render(assigns)

    text =
      module.text_render(assigns)
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()

    {html, text}
  end

  # Oban args round-trip through JSON, so the assigns arrive with string keys.
  # Every one of them is written literally in a `deliver_*` clause above, so the
  # atoms are guaranteed to exist by the time a job runs.
  defp atomize_keys(assigns) do
    Map.new(assigns, fn {key, value} -> {String.to_existing_atom(key), value} end)
  end

  defp from_address() do
    email = Application.fetch_env!(:nerves_hub, :from_email)
    sender = Application.fetch_env!(:nerves_hub, :email_sender)
    {sender, email}
  end

  defp platform_name(), do: Application.get_env(:nerves_hub, :support_email_platform_name)
end
