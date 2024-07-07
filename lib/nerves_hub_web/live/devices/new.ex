defmodule NervesHubWeb.Live.Devices.New do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Devices
  alias NervesHub.Devices.Device

  def mount(_params, _session, socket) do
    changeset = Ecto.Changeset.change(%Device{})

    socket =
      socket
      |> assign(:page_title, "New Device")
      |> assign(:form, to_form(changeset))

    {:ok, socket}
  end

  def handle_event("save-device", %{"device" => device_params}, socket) do
    authorized!(:"device:create", socket.assigns.org_user)

    %{product: product} = socket.assigns

    device_params
    |> Map.put("org_id", product.org.id)
    |> Map.put("product_id", product.id)
    |> Devices.create_device()
    |> case do
      {:ok, _device} ->
        socket
        |> put_flash(:info, "Device created successfully.")
        |> push_navigate(to: ~p"/products/#{hashid(product)}/devices")
        |> noreply()

      {:error, changeset} ->
        socket
        |> assign(:form, to_form(changeset))
        |> put_flash(:error, "Failed to add device.")
        |> noreply()
    end
  end
end
