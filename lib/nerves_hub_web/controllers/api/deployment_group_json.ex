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
      conditions: conditions(deployment_group.conditions),
      delta_updatable: deployment_group.delta_updatable
    }
  end

  defp conditions(conditions) do
    %{
      version: conditions.version,
      tags: conditions.tags
    }
  end
end
