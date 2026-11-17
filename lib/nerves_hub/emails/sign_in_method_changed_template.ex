defmodule NervesHub.Emails.SignInMethodChangedTemplate do
  use MjmlEEx, mjml_template: "sign_in_method_changed_template.mjml.eex"
  use NervesHubWeb, :html

  alias NervesHub.Emails.ClosingBlock

  def text_render(assigns) do
    ~H"""
    Hi {@user_name},

    {change_text(@change, @platform_name)}

    If this wasn't you, reset your password straight away, which signs you out everywhere else, then check how you sign in on your account page:

    {@reset_url}

    <ClosingBlock.text_support_section />
    """noformat
  end

  defp change_text("google_connected", platform_name),
    do: "A Google account is now connected to your #{platform_name} account, so you can sign in with Google."

  defp change_text("google_disconnected", platform_name),
    do:
      "Your Google account is no longer connected to your #{platform_name} account, so you sign in with your password."

  defp change_text("password_removed", platform_name),
    do: "Your #{platform_name} account no longer has a password, so you sign in with Google."
end
