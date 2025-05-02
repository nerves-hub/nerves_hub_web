defmodule NervesHub.Emails.PasswordResetTemplate do
  use MjmlEEx, mjml_template: "password_reset_template.mjml.eex"
  use NervesHubWeb, :html

  alias NervesHub.Emails.ClosingBlock

  def text_render(assigns) do
    ~H"""
    Hi {@user_name},

    You can reset your {@platform_name} password by visiting the URL below:

    {@reset_url}

    <ClosingBlock.text_support_section />
    """noformat
  end
end
