defmodule NervesHubWeb.Live.Orgs.Index do
  use NervesHubWeb, :updated_live_view

  def mount(params, _session, socket) do
    socket
    |> assign(:page_title, "Organizations")
    |> ok()
  end
end
