defmodule NervesHub.Emails.ClosingBlock do
  use MjmlEEx.Component, mode: :runtime
  use NervesHubWeb, :html

  alias Phoenix.HTML

  @impl MjmlEEx.Component
  def render(_assigns) do
    """
    <mj-section padding-top="0px">
      <mj-column>
        <mj-text font-size="20px" font-family="sans-serif">
        #{HTML.Safe.to_iodata(support_section())}
        </mj-text>
        #{HTML.Safe.to_iodata(signoff())}
      </mj-column>
    </mj-section>
    """
  end

  def support_section(assigns \\ %{}) do
    case Application.get_env(:nerves_hub, :support_email_address) do
      nil ->
        ~H"""
        If you run into problems, please contact your NervesHub admin.
        """

      email ->
        assigns = %{email: email}

        ~H"""
        If you have any questions, please email our <a href="mailto:{@email}">support team</a>.
        """
    end
  end

  def text_support_section(assigns \\ %{}) do
    case Application.get_env(:nerves_hub, :support_email_address) do
      nil ->
        ~H"""
        If you run into problems, please contact your NervesHub admin.
        """

      email ->
        assigns = %{email: email}

        ~H"""
        If you have any questions, please email our support team at {@email}.
        """
    end
  end

  defp signoff(assigns \\ %{}) do
    if signoff = Application.get_env(:nerves_hub, :support_email_signoff) do
      assigns = %{signoff: signoff}

      ~H"""
      <mj-text font-size="20px" font-family="sans-serif" padding-top="20px">
        Thanks
      </mj-text>
      <mj-text font-size="20px" font-family="sans-serif" padding-top="20px">
        {@signoff}
      </mj-text>
      """
    else
      ~H"""
      """
    end
  end
end
