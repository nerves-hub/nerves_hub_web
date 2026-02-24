defmodule NervesHubWeb.API.DeviceJSON do
  @moduledoc false

  @doc """
  Renders a list of devices.
  """
  def index(%{devices: devices, pagination: pagination}) do
    %{
      data: for(device <- devices, do: device(device)),
      pagination: pagination
    }
  end

  @doc """
  Renders a devices.
  """
  def show(%{device: device}) do
    %{
      data: device(device)
    }
  end

  defp device(device) do
    %{
      identifier: device.identifier,
      description: device.description,
      tags: device.tags,
      online: connection_status(device),
      connection_status: connection_status(device),
      firmware_metadata: device.firmware_metadata,
      version: version(device),
      deployment_group: deployment_group(device.deployment_group),
      updates_enabled: device.updates_enabled,
      updates_blocked_until: device.updates_blocked_until,
      # do we need these?
      org_name: device.org.name,
      product_name: device.product.name,
      # deprecated
      last_communication: connection_last_seen_at(device),
      deleted: deleted(device)
    }
  end

  defp deployment_group(nil), do: nil

  defp deployment_group(deployment_group) do
    %{
      firmware_uuid: deployment_group.current_release.firmware.uuid,
      firmware_version: deployment_group.current_release.firmware.version,
      is_active: deployment_group.is_active,
      name: deployment_group.name
    }
  end

  defp version(%{firmware_metadata: nil}), do: "unknown"
  defp version(%{firmware_metadata: %{version: vsn}}), do: vsn

  defp connection_last_seen_at(%{latest_connection: nil}), do: "never"

  defp connection_last_seen_at(%{latest_connection: latest_connection}), do: to_string(latest_connection.last_seen_at)

  defp connection_status(%{latest_connection: %{status: status}}), do: status
  defp connection_status(_), do: :not_seen

  defp deleted(%{deleted_at: nil}), do: false
  defp deleted(%{deleted_at: _}), do: true
end
