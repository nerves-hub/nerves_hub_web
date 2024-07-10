defmodule NervesHubWeb.Live.Devices.New do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Devices
  alias NervesHub.Devices.Device

  def mount(_params, _session, socket) do
    changeset = Ecto.Changeset.change(%Device{})

    socket =
      socket
      |> page_title("New Device - #{socket.assigns.product.name}")
      |> assign(:tab_hint, :devices)
      |> assign(:form, to_form(changeset))

    {:ok, socket}
  end

  def handle_event("save-device", %{"device" => device_params}, socket) do
    authorized!(:"device:create", socket.assigns.org_user)

    %{org: org, product: product} = socket.assigns

    device_params
    |> Map.put("org_id", org.id)
    |> Map.put("product_id", product.id)
    |> Devices.create_device()
    |> case do
      {:ok, _device} ->
        socket
        |> put_flash(:info, "Device created successfully.")
        |> push_navigate(to: ~p"/org/#{org.name}/#{product.name}/devices")
        |> noreply()

      {:error, changeset} ->
        socket
        |> assign(:form, to_form(changeset))
        |> put_flash(:error, "Failed to add device.")
        |> noreply()
    end
  end
end
