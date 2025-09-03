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
      conditions: deployment_group.conditions,
      delta_updatable: deployment_group.delta_updatable,
      firmware_uuid: deployment_group.firmware.uuid,
      is_active: deployment_group.is_active,
      name: deployment_group.name,
      state: if(deployment_group.is_active, do: "on", else: "off")
    }
  end
end
