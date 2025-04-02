defmodule NervesHubWeb.API.DeploymentGroupView do
  use NervesHubWeb, :api_view

  alias NervesHubWeb.API.DeploymentGroupView

  def render("index.json", %{deployment_groups: deployment_groups}) do
    %{data: render_many(deployment_groups, DeploymentGroupView, "deployment_group.json")}
  end

  def render("show.json", %{deployment_group: deployment_group}) do
    %{data: render_one(deployment_group, DeploymentGroupView, "deployment_group.json")}
  end

  def render("deployment_group.json", %{deployment_group: deployment_group}) do
    %{
      name: deployment_group.name,
      is_active: deployment_group.is_active,
      state: if(deployment_group.is_active, do: "on", else: "off"),
      firmware_uuid: deployment_group.firmware.uuid,
      conditions: deployment_group.conditions
    }
  end
end
