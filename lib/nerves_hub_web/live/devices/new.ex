defmodule NervesHubWeb.Live.Devices.New do
  use NervesHubWeb, :live_view

  alias NervesHub.Devices
  alias NervesHub.Devices.Device

  def mount(_params, _session, socket) do
    changeset = Ecto.Changeset.change(%Device{})

    socket
    |> page_title("New Device - #{socket.assigns.current_scope.product.name}")
    |> sidebar_tab(:devices)
    |> assign(:form, to_form(changeset))
    |> assign(:available_tags, Devices.distinct_tags_for_product(socket.assigns.current_scope.product))
    |> ok()
  end

  def handle_event("save-device", %{"device" => device_params}, socket) do
    authorized!(:"device:create", socket.assigns.current_scope)

    %{current_scope: %{org: org, product: product}} = socket.assigns

    device_params
    |> Map.put("org_id", org.id)
    |> Map.put("product_id", product.id)
    |> Devices.create_device()
    |> case do
      {:ok, _device} ->
        socket
        |> put_flash(:info, "Device created successfully.")
        |> push_navigate(to: ~p"/org/#{org}/#{product}/devices")
        |> noreply()

      {:error, changeset} ->
        socket
        |> assign(:form, to_form(changeset))
        |> put_flash(:error, "Failed to add new device.")
        |> noreply()
    end
  end
end
