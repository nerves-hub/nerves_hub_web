defmodule NervesHub.Emails.TwoFactorDisabledTemplate do
  use MjmlEEx, mjml_template: "two_factor_disabled_template.mjml.eex"
  use NervesHubWeb, :html

  alias NervesHub.Emails.ClosingBlock

  def text_render(assigns) do
    ~H"""
    Hi {@user_name},

    Two-factor authentication is now off for your {@platform_name} account. Signing in will only ask for your password.

    If this wasn't you, reset your password straight away, then turn two-factor authentication back on:

    {@reset_url}

    <ClosingBlock.text_support_section />
    """noformat
  end
end
