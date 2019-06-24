defmodule NervesHubWWWWeb.OrgCertificateController do
  use NervesHubWWWWeb, :controller

  alias NervesHubWebCore.Devices

  def index(%{assigns: %{org: org}} = conn, _params) do
    conn
    |> render(
      "index.html",
      certificates: Devices.get_ca_certificates(org)
    )
  end
end
