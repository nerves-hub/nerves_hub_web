defmodule NervesHubDeviceWeb.DeviceController do
  use NervesHubDeviceWeb, :controller
  alias NervesHubWebCore.Devices

  def me(%{assigns: %{device: device}} = conn, _params) do
    render(conn, "show.json", device: device)
  end

  def update(%{assigns: %{device: device}} = conn, _params) do
    deployments = Devices.get_eligible_deployments(device)
    join_reply = Devices.resolve_update(device.org, deployments)
    render(conn, "update.json", reply: join_reply)
  end
end
