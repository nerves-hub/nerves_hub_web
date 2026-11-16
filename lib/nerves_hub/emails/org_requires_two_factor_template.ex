defmodule NervesHub.Emails.OrgRequiresTwoFactorTemplate do
  use MjmlEEx, mjml_template: "org_requires_two_factor_template.mjml.eex"
  use NervesHubWeb, :html

  alias NervesHub.Emails.ClosingBlock

  def text_render(%{has_two_factor: true} = assigns) do
    ~H"""
    Hi {@user_name},

    {@admin_name} has made two-factor authentication required for every member of {@org_name}.

    You already have it on, so nothing changes for you.

    <ClosingBlock.text_support_section />
    """noformat
  end

  def text_render(assigns) do
    ~H"""
    Hi {@user_name},

    {@admin_name} has made two-factor authentication required for every member of {@org_name}.

    Until you turn it on, you won't be able to reach {@org_name}'s products, devices or settings. You'll need an authenticator app on your phone. Set it up here:

    {@setup_url}

    <ClosingBlock.text_support_section />
    """noformat
  end
end
