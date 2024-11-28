defmodule NervesHubWeb.Live.DeploymentGroup.Index do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Firmwares.Firmware

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{product: product}} = socket) do
    deployments = ManagedDeployments.get_deployments_by_product(product.id)
    counts = ManagedDeployments.get_deployment_device_counts_by_product(product.id)

    deployments =
      deployments
      |> Enum.sort_by(& &1.name)
      |> Enum.group_by(fn deployment ->
        deployment.firmware.platform
      end)

    socket
    |> page_title("Deployments - #{product.name}")
    |> assign(:deployment_groups, deployments)
    |> assign(:counts, counts)
    |> ok()
  end

  defp firmware_simple_display_name(%Firmware{} = f) do
    "#{f.version} #{f.uuid}"
  end

  defp version(%DeploymentGroup{conditions: %{"version" => ""}}), do: "-"
  defp version(%DeploymentGroup{conditions: %{"version" => version}}), do: version

  defp tags(%DeploymentGroup{conditions: %{"tags" => tags}}), do: tags
end
