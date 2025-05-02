defmodule NervesHub.Emails.TellOrgUserInvitedTemplate do
  use MjmlEEx, mjml_template: "tell_org_user_invited_template.mjml.eex"
  use NervesHubWeb, :html

  alias NervesHub.Emails.ClosingBlock

  def text_render(assigns) do
    ~H"""
    Hi {@user_name},

    *{@new_user_email}* has been invited to the *{@org_name}* organization by {@invited_by_name}.

    <ClosingBlock.text_support_section />
    """noformat
  end
end
