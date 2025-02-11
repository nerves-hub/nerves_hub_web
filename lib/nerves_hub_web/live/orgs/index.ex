defmodule NervesHubWeb.Live.Orgs.Index do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Devices
  alias NervesHubWeb.Components.PinnedDevices
  alias Number.Delimit

  def mount(_params, _session, %{assigns: %{user: user}} = socket) do
    socket
    |> assign(:page_title, "Organizations")
    |> assign(:pinned_devices, Devices.get_pinned_devices(user.id))
    |> ok()
  end

  defp format_device_count(nil), do: 0

  defp format_device_count(count) do
    Delimit.number_to_delimited(count, precision: 0)
  end
end
