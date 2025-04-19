defmodule NervesHub.Emails.TellOrgUserAddedTemplate do
  use MjmlEEx, mjml_template: "tell_org_user_added_template.mjml.eex"
  use NervesHubWeb, :html

  alias NervesHub.Emails.ClosingBlock

  def text_render(assigns) do
    ~H"""
    Hi {@user_name},

    *{@new_user_name}* has been added to the *{@org_name}* organization by {@invited_by_name}.

    <ClosingBlock.text_support_section />
    """noformat
    |> Phoenix.HTML.Safe.to_iodata()
  end
end
