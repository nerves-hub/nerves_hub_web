defmodule NervesHubWeb.API.DeviceView do
  use NervesHubWeb, :api_view

  alias NervesHub.Repo
  alias NervesHub.Tracker

  def render("index.json", %{devices: devices, pagination: pagination}) do
    %{
      data: render_many(devices, __MODULE__, "device.json"),
      pagination: pagination
    }
  end

  def render("show.json", %{device: device}) do
    %{data: render_one(device, __MODULE__, "device.json")}
  end

  def render("device.json", %{device: device}) do
    device = Repo.preload(device, :latest_connection)

    %{
      identifier: device.identifier,
      tags: device.tags,
      version: version(device),
      online: Tracker.sync_online?(device),
      connection_status: connection_status(device),
      # deprecated
      last_communication: connection_last_seen_at(device),
      description: device.description,
      firmware_metadata: device.firmware_metadata,
      deployment_group:
        render_one(device.deployment_group, __MODULE__, "deployment_group.json",
          as: :deployment_group
        ),
      updates_enabled: device.updates_enabled,
      updates_blocked_until: device.updates_blocked_until,
      org_name: device.org.name,
      product_name: device.product.name
    }
  end

  def render("deployment_group.json", %{deployment_group: deployment_group}) do
    %{
      firmware_uuid: deployment_group.firmware.uuid,
      firmware_version: deployment_group.firmware.version,
      is_active: deployment_group.is_active,
      name: deployment_group.name
    }
  end

  defp version(%{firmware_metadata: nil}), do: "unknown"
  defp version(%{firmware_metadata: %{version: vsn}}), do: vsn

  defp connection_last_seen_at(%{latest_connection: nil}), do: "never"

  defp connection_last_seen_at(%{latest_connection: latest_connection}),
    do: to_string(latest_connection.last_seen_at)

  defp connection_status(%{latest_connection: %{status: status}}), do: status
  defp connection_status(_), do: :not_seen
end
