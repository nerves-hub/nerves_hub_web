defmodule NervesHubWWWWeb.DeviceLive.Edit do
  use NervesHubWWWWeb, :live_view

  import NervesHubWebCore.AuditLogs, only: [audit!: 4]

  alias NervesHubWebCore.{
    Accounts,
    Devices,
    Devices.Device,
    Products
  }

  def render(assigns) do
    NervesHubWWWWeb.DeviceView.render("edit.html", assigns)
  end

  def mount(
        %{
          auth_user_id: user_id,
          org_id: org_id,
          product_id: product_id,
          device_id: device_id
        },
        socket
      ) do
    socket =
      socket
      |> assign_new(:user, fn -> Accounts.get_user!(user_id) end)
      |> assign_new(:org, fn -> Accounts.get_org!(org_id) end)
      |> assign_new(:product, fn -> Products.get_product!(product_id) end)
      |> assign_new(:device, fn -> Devices.get_device!(device_id) end)

    socket =
      socket
      |> assign(:changeset, Device.changeset(socket.assigns.device, %{}))

    {:ok, socket}
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
        %{
          assigns: %{
            device: device,
            org: org,
            product: product,
            user: user
          }
        } = socket
      ) do
    device
    |> Devices.update_device(device_params)
    |> case do
      {:ok, _updated_device} ->
        audit!(user, device, :update, device_params)

        {:stop,
         socket
         |> put_flash(:info, "Device Updated")
         |> redirect(
           to: Routes.device_path(socket, :show, org.name, product.name, device.identifier)
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end
end
