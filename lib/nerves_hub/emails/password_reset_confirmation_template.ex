defmodule NervesHub.Emails.PasswordResetConfirmationTemplate do
  use MjmlEEx, mjml_template: "password_reset_confirmation_template.mjml.eex"
  use NervesHubWeb, :html

  alias NervesHub.Emails.ClosingBlock

  def text_render(assigns) do
    ~H"""
    Hi {@user_name},

    You're {@platform_name} password has been reset.

    If you did not request a password reset, please ignore this email.

    <ClosingBlock.text_support_section />
    """noformat
    |> Phoenix.HTML.Safe.to_iodata()
  end
end
