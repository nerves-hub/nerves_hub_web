defmodule NervesHubWeb.Live.DeploymentGroups.Newz do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.AuditLogs.DeploymentGroupTemplates
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{product: product}} = socket) do
    if Firmwares.count(product) == 0 do
      socket
      |> assign(:firmware_required, true)
      |> ok()
    else
      platforms = Firmwares.get_unique_platforms(product)

      socket
      |> page_title("New Deployment - #{socket.assigns.product.name}")
      |> sidebar_tab(:deployments)
      |> assign(:firmware_required, false)
      |> assign(:platforms, platforms)
      |> assign(:architectures, [])
      |> assign(:platform, nil)
      |> assign(:architecture, nil)
      |> assign(:firmwares, [])
      |> assign(:form, to_form(ManagedDeployments.new_deployment_group()))
      |> ok()
    end
  end

  @impl Phoenix.LiveView
  def handle_event(
        "platform-selected",
        %{"deployment_group" => %{"platform" => platform}},
        socket
      ) do
    authorized!(:"deployment_group:create", socket.assigns.org_user)

    %{product: product} = socket.assigns

    architectures = Firmwares.get_unique_architectures(product)

    socket
    |> assign(:platform, platform)
    |> assign(:architectures, architectures)
    |> assign(:architecture, nil)
    |> assign(:firmwares, [])
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_event(
        "architecture-selected",
        %{"deployment_group" => %{"architecture" => architecture}},
        socket
      ) do
    authorized!(:"deployment_group:create", socket.assigns.org_user)

    %{product: product} = socket.assigns

    firmwares =
      Firmwares.get_firmwares(product, socket.assigns.platform, architecture)

    socket
    |> assign(:firmwares, firmwares)
    |> assign(:architecture, architecture)
    |> noreply()
  end

  # @impl Phoenix.LiveView
  def handle_event("create-deployment-group", %{"deployment_group" => params}, socket) do
    authorized!(:"deployment_group:create", socket.assigns.org_user)

    %{user: user, org: org, product: product} = socket.assigns

    params =
      params
      |> inject_conditions_map()
      |> whitelist([:name, :conditions, :firmware_id])
      |> Map.put(:org_id, org.id)
      |> Map.put(:is_active, false)

    org
    |> Firmwares.get_firmware(params[:firmware_id])
    |> case do
      {:ok, firmware} ->
        {firmware, ManagedDeployments.create_deployment_group(params)}

      {:error, :not_found} ->
        {:error, :not_found}
    end
    |> case do
      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Invalid firmware selected")
        |> noreply()

      {_, {:ok, deployment_group}} ->
        _ = DeploymentGroupTemplates.audit_deployment_created(user, deployment_group)

        socket
        |> put_flash(:info, "Deployment Group created")
        |> push_navigate(to: ~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}")
        |> noreply()

      {_firmware, {:error, changeset}} ->
        socket
        |> put_flash(:error, "There was an error creating the deployment")
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end

  defp firmware_dropdown_options(firmwares) do
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

  defp firmware_display_name(%Firmware{} = f) do
    "#{f.version} - #{f.uuid}"
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

  @doc """
  Convert tags from a list to a comma-separated list (in a string)
  """
  def tags_to_string(%Phoenix.HTML.FormField{} = field) do
    field.value ||
      %{}
      |> Map.get("tags", [])
      |> Enum.join(", ")
  end

  defp tags_as_list(""), do: []

  defp tags_as_list(tags) do
    tags
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end
end
