defmodule NervesHubWeb.DeviceEventsStreamChannel do
  @moduledoc """
  Phoenix Channel for external services to subscribe to device updates.
  Currently only supports firmware update progress.

  External services can join device-specific channels using the topic pattern "device:\#{device_identifier}"
  """

  use Phoenix.Channel

  alias NervesHub.Accounts
  alias NervesHub.Accounts.PubSub, as: AccessPubSub
  alias NervesHub.Devices
  alias NervesHub.Devices.PubSub
  alias NervesHubWeb.Helpers.Authorization
  alias Phoenix.Socket.Broadcast

  require Logger

  @impl Phoenix.Channel
  def join("device:" <> device_identifier, _params, socket) do
    # Socket already has authenticated user, just validate device access
    if authorized?(socket.assigns.user, device_identifier) do
      device = Devices.get_by_identifier!(device_identifier)
      :ok = PubSub.subscribe(device.id)
      :ok = AccessPubSub.subscribe_membership(device.org_id, socket.assigns.user.id)

      {:ok, assign(socket, :device_identifier, device_identifier)}
    else
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

  # The user's role in the device's org changed, or they were removed from it.
  # Checked the same way as on join, so a user who couldn't subscribe now
  # doesn't stay subscribed.
  def handle_info({:org_membership_changed, _org_id}, socket) do
    if authorized?(socket.assigns.user, socket.assigns.device_identifier) do
      {:noreply, socket}
    else
      {:stop, {:shutdown, :closed}, socket}
    end
  end

  def handle_info(msg, socket) do
    Logger.debug("[DeviceEventsStreamChannel] Unhandled handle_info message! - #{inspect(msg)}")

    {:noreply, socket}
  end

  defp authorized?(user, device_identifier) do
    case Accounts.find_org_user_with_device_identifier(user, device_identifier) do
      nil ->
        false

      org_user ->
        Authorization.authorized?(:"device:view", org_user)
    end
  end
end
