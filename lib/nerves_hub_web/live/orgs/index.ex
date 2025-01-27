defmodule NervesHubWeb.Live.Orgs.Index do
  use NervesHubWeb, :updated_live_view

  alias Number.Delimit

  def mount(_params, _session, socket) do
    socket
    |> assign(:page_title, "Organizations")
    |> ok()
  end

  defp format_device_count(nil), do: 0

  defp format_device_count(count) do
    Delimit.number_to_delimited(count, precision: 0)
  end
end
