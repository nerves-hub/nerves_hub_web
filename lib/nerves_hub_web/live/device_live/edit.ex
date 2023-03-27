defmodule NervesHubWeb.DeviceLive.Edit do
  use NervesHubWeb, :live_view

  require Logger

  alias NervesHub.AuditLogs
  alias NervesHub.Accounts
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Products

  def render(assigns) do
    NervesHubWeb.DeviceView.render("edit.html", assigns)
  end

  def mount(
        _params,
        %{
          "auth_user_id" => user_id,
          "org_id" => org_id,
          "product_id" => product_id,
          "device_id" => device_id
        },
        socket
      ) do
    socket =
      socket
      |> assign_new(:user, fn -> Accounts.get_user!(user_id) end)
      |> assign_new(:org, fn -> Accounts.get_org!(org_id) end)
      |> assign_new(:product, fn -> Products.get_product!(product_id) end)
      |> assign_new(:device, fn ->
        Devices.get_device_by_product(device_id, product_id, org_id)
      end)

    socket =
      socket
      |> assign(:changeset, Device.changeset(socket.assigns.device, %{}))

    {:ok, socket}
  rescue
    exception ->
      Logger.error(Exception.format(:error, exception, __STACKTRACE__))
      socket_error(socket, live_view_error(exception))
  end

  # Catch-all to handle when LV sessions change.
  # Typically this is after a deploy when the
  # session structure in the module has changed
  # for mount/3
  def mount(_, _, socket) do
    socket_error(socket, live_view_error(:update))
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
        AuditLogs.audit!(
          user,
          device,
          :update,
          "user #{user.username} updated device #{device.identifier}",
          device_params
        )

        {:noreply,
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
