defmodule NervesHubAPIWeb.DeploymentView do
  use NervesHubAPIWeb, :view
  alias NervesHubAPIWeb.DeploymentView

  def render("index.json", %{deployments: deployments}) do
    %{data: render_many(deployments, DeploymentView, "deployment.json")}
  end

  def render("show.json", %{deployment: deployment}) do
    %{data: render_one(deployment, DeploymentView, "deployment.json")}
  end

  def render("deployment.json", %{deployment: deployment}) do
    %{
      name: deployment.name,
      is_active: deployment.is_active,
      firmware_uuid: deployment.firmware.uuid,
      conditions: deployment.conditions
    }
  end
end
