defmodule NervesHub.Emails.UserInviteTemplate do
  use MjmlEEx, mjml_template: "user_invite_template.mjml.eex"
  use NervesHubWeb, :html

  alias NervesHub.Emails.ClosingBlock

  def text_render(assigns) do
    ~H"""
    Hi,

    You've been invited to join the {@org_name} organization on {@platform_name} by {@invited_by_name}.

    To get started click on the link below to register your account and set up your password:

    {@invite_url}

    <ClosingBlock.text_support_section />
    """noformat
    |> Phoenix.HTML.Safe.to_iodata()
  end
end
