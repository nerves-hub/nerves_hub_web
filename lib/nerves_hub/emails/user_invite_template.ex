defmodule NervesHub.Emails.UserInviteTemplate do
  use MjmlEEx, mjml_template: "user_invite_template.mjml.eex"
  use NervesHubWeb, :html

  alias NervesHub.Emails.ClosingBlock

  def text_render(assigns) do
    ~H"""
    Hi,

    You've been invited to join the {@org_name} organization on {@platform_name} by {@invited_by_name}.

    <%= if @has_account do %>To accept the invitation, click on the link below and sign in:<% else %>To accept the invitation, click on the link below to register your account:<% end %>

    {@invite_url}

    This invitation expires in 48 hours. If you weren't expecting it, you can ignore this email
    or decline the invitation from the link above.

    <ClosingBlock.text_support_section />
    """noformat
  end
end
