defmodule NervesHubWeb.Mounts.FetchDevice do
  import Phoenix.Component

  alias NervesHub.Devices

  def on_mount(:default, %{"device_identifier" => device_identifier}, _session, socket) do
    %{org: org} = socket.assigns

    socket = assign_new(socket, :device, fn ->
      {:ok, device} = Devices.get_device_by_identifier(org, device_identifier)
      device
    end)

    {:cont, socket}
  end
end
