defmodule NervesHub.Emails.OrgUserAddedTemplate do
  use MjmlEEx, mjml_template: "org_user_added_template.mjml.eex"
  use NervesHubWeb, :html

  alias NervesHub.Emails.ClosingBlock

  def text_render(assigns) do
    ~H"""
    Hi {@user_name},

    You've been added to the *{@org_name}* organization by {@invited_by_name}.

    <ClosingBlock.text_support_section />
    """noformat
  end
end
