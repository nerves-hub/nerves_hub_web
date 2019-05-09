defmodule NervesHubWWWWeb.DeviceLive.Edit do
  use NervesHubWWWWeb, :live_view

  import NervesHubWebCore.AuditLogs, only: [audit!: 4]

  alias NervesHubWebCore.{
    Accounts.Org,
    Accounts.User,
    Devices,
    Devices.Device
  }

  def render(assigns) do
    NervesHubWWWWeb.DeviceView.render("edit.html", assigns)
  end

  def mount(
        %{auth_user_id: user_id, current_org_id: org_id, path_params: %{"id" => device_id}},
        socket
      ) do
    case Devices.get_device_by_org(%Org{id: org_id}, device_id) do
      {:ok, device} ->
        socket =
          socket
          |> assign(:device, device)
          |> assign(:changeset, Device.changeset(device, %{}))
          |> assign(:user_id, user_id)

        {:ok, socket}

      {:error, :not_found} ->
        {:stop,
         socket
         |> put_flash(:error, "Device not found")
         |> redirect(to: "/devices")}
    end
  end

  def handle_event("validate", %{"device" => device_params}, socket) do
    changeset =
      socket.assigns.device
      |> Device.changeset(device_params)
      |> Map.put(:action, :insert)

    {:noreply, assign(socket, changeset: changeset)}
  end

  def handle_event(
        "save",
        %{"device" => device_params},
        %{assigns: %{device: device, user_id: user_id}} = socket
      ) do
    device
    |> Devices.update_device(device_params)
    |> case do
      {:ok, _updated_device} ->
        audit!(%User{id: user_id}, device, :update, device_params)

        {:stop,
         socket
         |> put_flash(:info, "Device Updated")
         |> redirect(to: Routes.device_path(socket, DeviceLive.Show, device))}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end
end
