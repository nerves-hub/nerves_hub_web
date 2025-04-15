defmodule NervesHub.Emails.TellOrgUserRemovedTemplate do
  use MjmlEEx, mjml_template: "tell_org_user_removed_template.mjml.eex"
  use NervesHubWeb, :html

  alias NervesHub.Emails.ClosingBlock

  def text_render(assigns) do
    ~H"""
    Hi {@user_name},

    *{@removed_user_name}* has been removed from the *{@org_name}* organization by {@instigator_name}.

    <ClosingBlock.text_support_section />
    """noformat
    |> Phoenix.HTML.Safe.to_iodata()
  end
end
