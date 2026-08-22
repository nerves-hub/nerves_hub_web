defmodule NervesHubWeb.DeviceEventsStreamChannel do
  @moduledoc """
  Phoenix Channel for external services to subscribe to device updates.
  Currently only supports firmware update progress.

  External services can join device-specific channels using the topic pattern "device:\#{device_identifier}"
  """

  use Phoenix.Channel

  alias NervesHub.Accounts
  alias NervesHub.Devices
  alias NervesHubWeb.Helpers.Authorization
  alias Phoenix.Socket.Broadcast

  require Logger

  @impl Phoenix.Channel
  def join("device:" <> device_identifier, _params, socket) do
    # Socket already has authenticated user, just validate device access
    if authorized?(socket.assigns.user, device_identifier) do
      device = Devices.get_by_identifier!(device_identifier)
      :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "internal:device:#{device.id}")

      {:ok, socket}
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
