defmodule NervesHub.Emails.WelcomeTemplate do
  use MjmlEEx, mjml_template: "welcome_template.mjml.eex"
  use NervesHubWeb, :html

  alias NervesHub.Emails.ClosingBlock

  def text_render(assigns) do
    ~H"""
    Hi {@user_name},

    Welcome to {@platform_name}!

    <ClosingBlock.text_support_section />
    """noformat
  end
end
