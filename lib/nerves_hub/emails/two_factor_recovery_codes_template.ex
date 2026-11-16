defmodule NervesHub.Emails.TwoFactorRecoveryCodesTemplate do
  use MjmlEEx, mjml_template: "two_factor_recovery_codes_template.mjml.eex"
  use NervesHubWeb, :html

  alias NervesHub.Emails.ClosingBlock

  def text_render(assigns) do
    ~H"""
    Hi {@user_name},

    New two-factor recovery codes were made for your {@platform_name} account. Your old recovery codes no longer work.

    If this wasn't you, someone has your password and your authenticator app or a recovery code. Reset your password straight away, then make new recovery codes:

    {@manage_url}

    <ClosingBlock.text_support_section />
    """noformat
  end
end
