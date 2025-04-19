defmodule NervesHub.Emails.PasswordUpdatedTemplate do
  use MjmlEEx, mjml_template: "password_updated_template.mjml.eex"
  use NervesHubWeb, :html

  alias NervesHub.Emails.ClosingBlock

  def text_render(assigns) do
    ~H"""
    Hi {@user_name},

    We wanted to let you know that your password has been updated.

    If this wasn't you, you can reset your {@platform_name} password by visiting the URL below:

    {@reset_url}

    <ClosingBlock.text_support_section />
    """noformat
    |> Phoenix.HTML.Safe.to_iodata()
  end
end
