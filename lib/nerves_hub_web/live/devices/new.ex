defmodule NervesHubWeb.Live.Devices.New do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Devices
  alias NervesHub.Devices.Device

  embed_templates("product_templates/*")

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket
    |> page_title("New Device - #{socket.assigns.org.name}")
    |> assign(:form, Ecto.Changeset.change(%Device{}))
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_event("create_device", %{"device" => device_params}, socket) do
    authorized!(:create_device, socket.assigns.org_user)

    device_params
    |> Map.put("org_id", socket.assigns.org.id)
    |> Map.put("product_id", socket.assigns.product.id)
    |> Devices.create_device()
    |> case do
      {:ok, _device} ->
        socket
        |> put_flash(:info, "Device added successfully")
        |> push_navigate(to: ~p"/org/#{socket.assigns.org.name}/#{socket.assigns.product.name}/devices")
        |> noreply()

      {:error, changeset} ->
        socket
        |> put_flash(:error, "Failed to add device.")
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end
end
