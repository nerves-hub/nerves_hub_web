defmodule NervesHub.Emails.ConfirmationTemplate do
  use MjmlEEx, mjml_template: "confirmation_template.mjml.eex"
  use NervesHubWeb, :html

  alias NervesHub.Emails.ClosingBlock

  def text_render(assigns) do
    ~H"""
    Hi {@user_name},

    Thanks for creating an account with {@platform_name}.

    Please use the link below to confirm your account:

    {@confirmation_url}

    <ClosingBlock.text_support_section />
    """noformat
    |> Phoenix.HTML.Safe.to_iodata()
  end
end
