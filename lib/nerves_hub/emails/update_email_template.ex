defmodule NervesHub.Emails.UpdateEmailTemplate do
  use MjmlEEx, mjml_template: "update_email_template.mjml.eex"
  use NervesHubWeb, :html

  alias NervesHub.Emails.ClosingBlock

  def text_render(assigns) do
    ~H"""
    Hi {@user_name},

    You asked to change the email address on your {@platform_name} account to this one.

    Please use the link below, while signed in to {@platform_name}, to confirm the change:

    {@confirmation_url}

    If you didn't ask for this, you can ignore this email and nothing will change.

    <ClosingBlock.text_support_section />
    """noformat
  end
end
