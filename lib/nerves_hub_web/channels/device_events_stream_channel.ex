defmodule NervesHubWeb.DeviceEventsStreamChannel do
  @moduledoc """
  Phoenix Channel for external services to subscribe to device updates.
  Currently only supports firmware update progress.

  External services can join device-specific channels using the topic pattern "device:\#{device_identifier}"
  """

  use Phoenix.Channel

  alias NervesHub.Accounts
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.PubSub, as: AccessPubSub
  alias NervesHub.Accounts.Scope
  alias NervesHub.Devices
  alias NervesHub.Devices.PubSub
  alias NervesHubWeb.Helpers.Authorization
  alias Phoenix.Socket.Broadcast

  require Logger

  @impl Phoenix.Channel
  def join("device:" <> device_identifier, _params, socket) do
    # Socket already has authenticated user, just validate device access
    case authorized_device(socket.assigns.user, device_identifier) do
      {:ok, device} ->
        :ok = PubSub.subscribe(device.id)
        :ok = AccessPubSub.subscribe_access(socket.assigns.user.id, device.id)

        {:ok, assign(socket, :device_identifier, device_identifier)}

      :error ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  # `NervesHub.FirmwareUpdates` broadcasts `firmware_update_progress` with string
  # keys. This previously matched on `fwup_progress` with a `:percent` atom key —
  # neither of which is ever broadcast — so nothing was forwarded to external
  # subscribers.
  @impl Phoenix.Channel
  def handle_info(%Broadcast{event: "firmware_update_progress", payload: payload}, socket) do
    # Forward the firmware update progress to the connected client
    push(socket, "firmware_update", %{percent: payload["progress"], stage: payload["stage"]})

    {:noreply, socket}
  end

  # The device's tags or the user's role changed. Checked the same way as on
  # join; a user who couldn't subscribe now doesn't stay subscribed.
  def handle_info(:access_changed, socket) do
    case authorized_device(socket.assigns.user, socket.assigns.device_identifier) do
      {:ok, _device} -> {:noreply, socket}
      :error -> {:stop, {:shutdown, :closed}, socket}
    end
  end

  def handle_info(msg, socket) do
    Logger.debug("[DeviceEventsStreamChannel] Unhandled handle_info message! - #{inspect(msg)}")

    {:noreply, socket}
  end

  # Looked up through the user, so a device their role can't see isn't found.
  defp authorized_device(user, device_identifier) do
    with {:ok, device} <- Devices.get_by_identifier(Scope.for_user(user), device_identifier),
         %OrgUser{} = org_user <- Accounts.find_org_user_with_device(user, device.id),
         true <- Authorization.authorized?(:"device:view", org_user) do
      {:ok, device}
    else
      _ -> :error
    end
  end
end
