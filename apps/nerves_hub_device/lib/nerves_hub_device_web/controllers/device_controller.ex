defmodule NervesHubDeviceWeb.DeviceController do
  use NervesHubDeviceWeb, :controller
  alias NervesHubWebCore.{Devices, Firmwares, Deployments}

  @uploader Application.get_env(:nerves_hub_web_core, :firmware_upload)

  def me(%{assigns: %{device: device}} = conn, _params) do
    render(conn, "show.json", device: device)
  end

  def update(%{assigns: %{device: device}} = conn, _params) do
    deployments = Devices.get_eligible_deployments(device)
    join_reply = resolve_update(device.org, deployments)
    render(conn, "update.json", reply: join_reply)
  end

  defp resolve_update(_org, _deployments = []), do: %{update_available: false}

  defp resolve_update(org, [%Deployments.Deployment{} = deployment | _]) do
    with {:ok, firmware} <- Firmwares.get_firmware(org, deployment.firmware_id),
         {:ok, url} <- @uploader.download_file(firmware) do
      %{update_available: true, firmware_url: url}
    else
      _ -> %{update_available: false}
    end
  end
end
