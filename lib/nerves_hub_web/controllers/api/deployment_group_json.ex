defmodule NervesHubWeb.API.DeploymentGroupJSON do
  @moduledoc false

  def index(%{deployment_groups: deployment_groups}) do
    %{data: for(dp <- deployment_groups, do: deployment_group(dp))}
  end

  def show(%{deployment_group: deployment_group}) do
    %{data: deployment_group(deployment_group)}
  end

  def deployment_group(deployment_group) do
    %{
      name: deployment_group.name,
      is_active: deployment_group.is_active,
      state: if(deployment_group.is_active, do: "on", else: "off"),
      firmware_uuid: deployment_group.current_release.firmware.uuid,
      current_release: current_release(deployment_group.current_release),
      archive_uuid: get_in(deployment_group.current_release.archive.uuid),
      conditions: conditions(deployment_group.conditions),
      delta_updatable: deployment_group.delta_updatable,
      device_count: deployment_group.device_count,
      releases_count: deployment_group.releases_count
    }
  end

  defp current_release(release) do
    %{
      number: release.number,
      firmware: firmware(release.firmware),
      inserted_at: release.inserted_at,
      updated_at: release.updated_at
    }
  end

  defp firmware(firmware) do
    %{
      version: firmware.version,
      architecture: firmware.architecture,
      platform: firmware.platform,
      uuid: firmware.uuid
    }
  end

  defp conditions(conditions) do
    %{
      version: conditions.version,
      tags: conditions.tags
    }
  end
end
