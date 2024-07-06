defmodule NervesHubWeb.Live.Orgs.Index do
  use NervesHubWeb, :updated_live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Organizations")}
  end
end
