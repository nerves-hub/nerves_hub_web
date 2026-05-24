defmodule NervesHub.Emails.TellOrgUserRemovedThemselfTemplate do
  use MjmlEEx, mjml_template: "tell_org_user_removed_themself_template.mjml.eex"
  use NervesHubWeb, :html

  alias NervesHub.Emails.ClosingBlock

  def text_render(assigns) do
    ~H"""
    Hi {@user_name},

    *{@removed_user_name}* has removed themself from the *{@org_name}* organization.

    <ClosingBlock.text_support_section />
    """noformat
  end
end
