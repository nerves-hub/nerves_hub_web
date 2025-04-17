defmodule NervesHubWeb.Live.DeploymentGroups.Edit do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Archives
  alias NervesHub.AuditLogs.DeploymentGroupTemplates
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    %{"name" => name} = params
    %{product: product} = socket.assigns

    deployment_group = ManagedDeployments.get_by_product_and_name!(product, name)

    current_device_count = ManagedDeployments.get_device_count(deployment_group)

    archives = Archives.all_by_product(deployment_group.product)
    firmwares = Firmwares.get_firmwares_for_deployment_group(deployment_group)

    changeset = DeploymentGroup.changeset(deployment_group, %{}) |> tags_to_string()

    socket
    |> assign(:archives, archives)
    |> sidebar_tab(:deployments)
    |> assign(:deployment_group, deployment_group)
    |> assign(:current_device_count, current_device_count)
    |> assign(:firmware, deployment_group.firmware)
    |> assign(:firmwares, firmwares)
    |> assign(:form, to_form(changeset))
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_event("update-deployment-group", %{"deployment_group" => params}, socket) do
    %{
      org_user: org_user,
      org: org,
      product: product,
      user: user,
      deployment_group: deployment_group
    } =
      socket.assigns

    authorized!(:"deployment_group:update", org_user)

    params = inject_conditions_map(params)

    case ManagedDeployments.update_deployment_group(deployment_group, params) do
      {:ok, updated} ->
        # Use original deployment so changes will get
        # marked in audit log
        DeploymentGroupTemplates.audit_deployment_updated(user, updated)

        socket
        |> put_flash(:info, "Deployment Group updated")
        |> push_navigate(to: ~p"/org/#{org}/#{product}/deployment_groups/#{updated}")
        |> noreply()

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(tags_to_string(changeset)))}
    end
  end

  defp inject_conditions_map(%{"version" => version, "tags" => tags} = params) do
    params
    |> Map.put("conditions", %{
      "version" => version,
      "tags" =>
        tags
        |> tags_as_list()
        |> MapSet.new()
        |> MapSet.to_list()
    })
  end

  defp inject_conditions_map(params), do: params

  defp tags_as_list(""), do: []

  defp tags_as_list(tags) do
    tags
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end

  def firmware_dropdown_options(firmwares) do
    firmwares
    |> Enum.sort_by(
      fn firmware ->
        case Version.parse(firmware.version) do
          {:ok, version} ->
            version

          :error ->
            %Version{major: 0, minor: 0, patch: 0}
        end
      end,
      {:desc, Version}
    )
    |> Enum.map(&[value: &1.id, key: firmware_display_name(&1)])
  end

  def archive_dropdown_options(archives) do
    archives
    |> Enum.sort_by(
      fn archive ->
        case Version.parse(archive.version) do
          {:ok, version} ->
            version

          :error ->
            %Version{major: 0, minor: 0, patch: 0}
        end
      end,
      {:desc, Version}
    )
    |> Enum.map(&[value: &1.id, key: archive_display_name(&1)])
  end

  def archive_display_name(%{} = a) do
    "#{a.version} #{a.platform} #{a.architecture} #{a.uuid}"
  end

  defp help_message_for(field) do
    case field do
      :failure_threshold ->
        "Maximum number of target devices from this deployment group that can be in an unhealthy state before deployment group is marked unhealthy"

      :failure_rate ->
        "Maximum number of device install failures from this deployment group within X seconds before being marked unhealthy"

      :device_failure_rate ->
        "Maximum number of device failures within X seconds a device can have for this deployment group before being marked unhealthy"

      :device_failure_threshold ->
        "Maximum number of install attempts and/or failures a device can have for this deployment group before being marked unhealthy"

      :penalty_timeout_minutes ->
        "Number of minutes a device is placed in the penalty box for reaching the failure rate and threshold"
    end
  end

  defp firmware_display_name(%Firmware{} = f) do
    "#{f.version} #{f.platform} #{f.architecture} #{f.uuid}"
  end

  @doc """
  Convert tags from a list to a comma-separated list (in a string)
  """
  def tags_to_string(%Ecto.Changeset{} = changeset) do
    conditions =
      changeset
      |> Ecto.Changeset.get_field(:conditions)

    tags =
      conditions
      |> Map.get("tags", [])
      |> Enum.join(",")

    conditions = Map.put(conditions, "tags", tags)

    changeset
    |> Ecto.Changeset.put_change(:conditions, conditions)
  end
end
