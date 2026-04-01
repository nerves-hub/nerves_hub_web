defmodule NervesHubWeb.Live.DeploymentGroups.New do
  use NervesHubWeb, :live_view

  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    if Firmwares.count(scope.product) == 0 do
      socket
      |> assign(:firmware_required, true)
      |> sidebar_tab(:deployments)
      |> ok()
    else
      platforms = Firmwares.get_unique_platforms(scope.product)

      socket
      |> page_title("New Deployment - #{scope.product.name}")
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
        "update-form",
        %{"_target" => ["deployment_group", "platform"], "deployment_group" => %{"platform" => platform}},
        socket
      ) do
    authorized!(:"deployment_group:create", socket.assigns.current_scope)

    architectures = Firmwares.get_unique_architectures(socket.assigns.current_scope.product)

    socket
    |> assign(:platform, platform)
    |> assign(:architectures, architectures)
    |> assign(:architecture, nil)
    |> assign(:firmwares, [])
    |> noreply()
  end

  def handle_event(
        "update-form",
        %{"_target" => ["deployment_group", "architecture"], "deployment_group" => %{"architecture" => architecture}},
        socket
      ) do
    authorized!(:"deployment_group:create", socket.assigns.current_scope)

    firmwares =
      Firmwares.get_firmwares(socket.assigns.current_scope.product, socket.assigns.platform, architecture)

    socket
    |> assign(:firmwares, firmwares)
    |> assign(:architecture, architecture)
    |> noreply()
  end

  def handle_event("update-form", _data, socket) do
    # noop all other changed fields
    {:noreply, socket}
  end

  def handle_event("recover-form", %{"deployment_group" => params}, socket) do
    socket
    |> assign(:form, to_form(params, as: :deployment_group))
    |> then(fn socket ->
      if platform = socket.assigns.form["platform"].value do
        architectures = Firmwares.get_unique_architectures(socket.assigns.current_scope.product)

        socket
        |> assign(:platform, platform)
        |> assign(:architectures, architectures)
      else
        socket
      end
    end)
    |> then(fn socket ->
      if architecture = socket.assigns.form["architecture"].value do
        %{current_scope: scope} = socket.assigns

        firmwares =
          Firmwares.get_firmwares(scope.product, socket.assigns.platform, architecture)

        socket
        |> assign(:firmwares, firmwares)
        |> assign(:architecture, architecture)
      else
        socket
      end
    end)
    |> noreply()
  end

  # def handle_event("platform-selected", %{"deployment_group" => %{"platform" => platform}}, socket) do
  #   authorized!(:"deployment_group:create", socket.assigns.current_scope)

  #   %{product: product} = socket.assigns

  #   raise("here: #{platform}")

  #   architectures = Firmwares.get_unique_architectures(product)

  #   dbg(architectures)

  #   socket
  #   |> assign(:platform, platform)
  #   |> assign(:architectures, architectures)
  #   |> assign(:architecture, nil)
  #   |> assign(:firmwares, [])
  #   |> noreply()
  # end

  # def handle_event("architecture-selected", %{"deployment_group" => %{"architecture" => architecture}}, socket) do
  #   authorized!(:"deployment_group:create", socket.assigns.current_scope)

  #   dbg("here: #{architecture}")

  #   %{product: product} = socket.assigns

  #   firmwares =
  #     Firmwares.get_firmwares(product, socket.assigns.platform, architecture)

  #   socket
  #   |> assign(:firmwares, firmwares)
  #   |> assign(:architecture, architecture)
  #   |> noreply()
  # end

  def handle_event("create-deployment-group", %{"deployment_group" => params}, socket) do
    authorized!(:"deployment_group:create", socket.assigns.current_scope)

    %{user: user, org: org, product: product} = socket.assigns.current_scope

    firmware = Firmwares.get_by_id(product, params["firmware"])

    ManagedDeployments.create_deployment_group(params, product, firmware, user)
    |> case do
      {:ok, deployment_group} ->
        socket
        |> put_flash(:info, "Deployment Group created")
        |> push_navigate(to: ~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}")
        |> noreply()

      {:error, changeset} ->
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
end
