defmodule NervesHubWeb.Live.Orgs.Index do
  use NervesHubWeb.LiveView

  def mount(_params, _session, socket) do
    socket
    |> assign(:page_title, "Organizations")
    |> ok()
  end
end
