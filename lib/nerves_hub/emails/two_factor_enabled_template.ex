defmodule NervesHub.Emails.TwoFactorEnabledTemplate do
  use MjmlEEx, mjml_template: "two_factor_enabled_template.mjml.eex"
  use NervesHubWeb, :html

  alias NervesHub.Emails.ClosingBlock

  def text_render(assigns) do
    ~H"""
    Hi {@user_name},

    Two-factor authentication is now on for your {@platform_name} account. Signing in will ask for a code from your authenticator app after your password.

    Keep your recovery codes somewhere safe. Each one signs you in once if you lose your phone.

    If this wasn't you, someone else has your password, and you'll need a recovery code to sign in. You can manage two-factor authentication here:

    {@manage_url}

    <ClosingBlock.text_support_section />
    """noformat
  end
end
