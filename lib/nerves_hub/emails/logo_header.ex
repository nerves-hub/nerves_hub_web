defmodule NervesHub.Emails.LogoHeader do
  use MjmlEEx.Component, mode: :runtime
  use NervesHubWeb, :html

  @impl MjmlEEx.Component
  def render(_assigns) do
    logo_url = static_url(NervesHubWeb.Endpoint, "/images/nerveshub-logo.png")

    """
    <mj-section  padding="10px 0">
      <mj-column>
        <mj-image width="200px" align="left" src="#{logo_url}"></mj-image>
        <mj-divider padding-top="20px" border-width="2px" border-color="#6366f1"></mj-divider>
      </mj-column>
    </mj-section>
    """
  end
end
