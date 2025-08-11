defmodule NervesHub.Emails.LoginWithGoogleReminderTemplate do
  use MjmlEEx, mjml_template: "login_with_google_reminder_template.mjml.eex"
  use NervesHubWeb, :html

  alias NervesHub.Emails.ClosingBlock

  def text_render(assigns) do
    ~H"""
    Hi {@user_name},

    We have received a request to reset your password.

    As your account was created using Google, there is no need to reset your password.

    Please use the Google login button on the login page to access your account.

    <ClosingBlock.text_support_section />
    """noformat
  end
end
