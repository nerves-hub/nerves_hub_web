defmodule NervesHubWeb.Live.Orgs.Index do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Devices
  alias NervesHubWeb.Components.PinnedDevices
  alias Number.Delimit

  @pinned_devices_limit 5

  def mount(_params, _session, %{assigns: %{user: user}} = socket) do
    socket
    |> assign(:page_title, "Organizations")
    |> assign(:show_all_pinned?, false)
    |> assign(:pinned_devices, Devices.get_pinned_devices(user.id))
    |> assign(:device_limit, @pinned_devices_limit)
    |> ok()
  end

  def handle_event(
        "toggle-expand-devices",
        _,
        %{assigns: %{show_all_pinned?: show_all?}} = socket
      ) do
    socket
    |> assign(:show_all_pinned?, !show_all?)
    |> noreply()
  end

  defp limit_devices(devices) do
    {limited_devices, _} = Enum.split(devices, @pinned_devices_limit)

    limited_devices
  end

  defp format_device_count(nil), do: 0

  defp format_device_count(count) do
    Delimit.number_to_delimited(count, precision: 0)
  end
end
