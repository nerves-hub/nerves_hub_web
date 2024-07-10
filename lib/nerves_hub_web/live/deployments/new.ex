defmodule NervesHubWeb.Live.Deployments.New do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.AuditLogs
  alias NervesHub.Deployments
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{org: org, product: product}} = socket) do
    firmware = Firmwares.get_firmwares_by_product(socket.assigns.product.id)

    if Enum.empty?(firmware) do
      socket
      |> put_flash(:error, "You must upload a firmware version before creating a deployment")
      |> push_navigate(to: ~p"/org/#{org.name}/#{product.name}/firmware/upload")
      |> ok()
    else
      platforms =
        firmware
        |> Enum.map(& &1.platform)
        |> Enum.uniq()

      socket
      |> page_title("New Deployment - #{socket.assigns.product.name}")
      |> assign(:platforms, platforms)
      |> assign(:platform, nil)
      |> assign(:form, to_form(Ecto.Changeset.change(%Deployment{})))
      |> ok()
    end
  end

  @impl Phoenix.LiveView
  def handle_event("select-platform", %{"deployment" => %{"platform" => platform}}, socket) do
    authorized!(:"deployment:create", socket.assigns.org_user)

    %{product: product} = socket.assigns

    firmwares = Firmwares.get_firmwares_by_product(product.id)

    firmwares =
      Enum.filter(firmwares, fn firmware ->
        firmware.platform == platform
      end)

    socket
    |> assign(:firmwares, firmwares)
    |> assign(:form, to_form(Ecto.Changeset.change(%Deployment{})))
    |> assign(:platform, platform)
    |> noreply()
  end

  # @impl Phoenix.LiveView
  def handle_event("create-deployment", %{"deployment" => params}, socket) do
    authorized!(:"deployment:create", socket.assigns.org_user)

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
        {firmware, Deployments.create_deployment(params)}

      {:error, :not_found} ->
        {:error, :not_found}
    end
    |> case do
      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Invalid firmware selected")
        |> noreply()

      {_, {:ok, deployment}} ->
        AuditLogs.audit!(
          user,
          deployment,
          "#{user.name} created deployment #{deployment.name}"
        )

        socket
        |> put_flash(:info, "Deployment created")
        |> push_navigate(to: ~p"/org/#{org.name}/#{product.name}/deployments")
        |> noreply()

      {_firmware, {:error, changeset}} ->
        socket
        |> assign(:form, to_form(changeset |> tags_to_string()))
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
    "#{f.version} #{f.platform} #{f.architecture} #{f.uuid}"
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

  defp tags_as_list(""), do: []

  defp tags_as_list(tags) do
    tags
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end
end
