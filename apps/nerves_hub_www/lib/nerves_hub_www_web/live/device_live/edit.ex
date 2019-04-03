defmodule NervesHubWWWWeb.DeviceLive.Edit do
  use Phoenix.LiveView

  alias NervesHubWWWWeb.Router.Helpers, as: Routes

  alias NervesHubWebCore.Devices
  alias NervesHubWebCore.Devices.Device

  def render(assigns) do
    NervesHubWWWWeb.DeviceView.render("edit.html", assigns)
  end

  def mount(session, socket) do
    socket =
      socket
      |> assign(:device, session.device)
      |> assign(:changeset, session.changeset)

    {:ok, socket}
  end

  def handle_event("validate", %{"device" => device_params}, socket) do
    changeset =
      socket.assigns.device
      |> Device.changeset(device_params)
      |> Map.put(:action, :insert)

    {:noreply, assign(socket, changeset: changeset)}
  end

  def handle_event("save", %{"device" => device_params}, socket) do
    socket.assigns.device
    |> Devices.update_device(device_params)
    |> case do
      {:ok, device} ->
        {:stop,
         socket
         |> put_flash(:info, "Device Updated")
         |> redirect(to: Routes.device_path(socket, :show, device))}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end
end
