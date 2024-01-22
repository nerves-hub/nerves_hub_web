defmodule NervesHubWeb.API.DeviceView do
  use NervesHubWeb, :api_view

  alias NervesHub.Devices

  def render("index.json", %{devices: devices, pagination: pagination}) do
    %{
      data: render_many(devices, __MODULE__, "device.json"),
      pagination: pagination
    }
  end

  def render("show.json", %{device: device}) do
    %{data: render_one(device, __MODULE__, "device.json")}
  end

  # TODO fix the online status for devices, it's always going to be wrong
  # in the current state of quesiton/answer
  def render("device.json", %{device: device}) do
    %{
      identifier: device.identifier,
      tags: device.tags,
      version: version(device),
      online: false,
      last_communication: last_communication(device),
      description: device.description,
      firmware_metadata: device.firmware_metadata,
      firmware_update_status: Devices.firmware_status(device),
      deployment: render_one(device.deployment, __MODULE__, "deployment.json", as: :deployment),
      updates_enabled: device.updates_enabled,
      updates_blocked_until: device.updates_blocked_until,
      org_name: device.org.name,
      product_name: device.product.name
    }
  end

  def render("deployment.json", %{deployment: deployment}) do
    %{
      firmware_uuid: deployment.firmware.uuid,
      firmware_version: deployment.firmware.version,
      is_active: deployment.is_active,
      name: deployment.name
    }
  end

  defp version(%{firmware_metadata: nil}), do: "unknown"
  defp version(%{firmware_metadata: %{version: vsn}}), do: vsn

  defp last_communication(%{last_communication: nil}), do: "never"
  defp last_communication(%{last_communication: dt}), do: to_string(dt)
end
