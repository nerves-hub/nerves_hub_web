defmodule NervesHubWeb.Live.Devices.Edit do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Devices

  import NervesHubWeb.DeviceView, only: [tags_to_string: 1]

  on_mount NervesHubWeb.Mounts.FetchDevice

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket
    |> page_title("Edit Device - #{socket.assigns.device.identifier} - #{socket.assigns.org.name}")
    |> assign(:form, Ecto.Changeset.change(socket.assigns.device))
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_event("update_device", %{"device" => device_params}, socket) do
    authorized!(:update_device, socket.assigns.org_user)

      %{user: user, org: org, product: product, device: device} = socket.assigns

      message = "#{user.name} updated device #{device.identifier}"

      case Devices.update_device_with_audit(device, device_params, user, message) do
        {:ok, device} ->
          socket
          |> put_flash(:info, "Device updated")
          |> push_navigate(to: ~p"/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
          |> noreply()

        {:error, changeset} ->
          socket
          |> assign(:form, to_form(changeset))
          |> noreply()
      end
  end
end
