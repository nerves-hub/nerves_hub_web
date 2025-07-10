defmodule NervesHubWeb.ExternalDeviceListenerChannel do
  @moduledoc """
  Phoenix Channel for external services to subscribe to device updates.
  Currently only supports firmware update progress.

  External services can join device-specific channels using the topic pattern "device:\#{device_identifier}"
  """

  use Phoenix.Channel

  require Logger

  alias NervesHub.Accounts
  alias NervesHub.Devices

  #######################################
  # Public API for broadcasting updates #
  #######################################

  def broadcast_firmware_update(device, percent) do
    NervesHubWeb.Endpoint.broadcast("device:#{device.identifier}", "firmware_update", %{
      percent: percent
    })
  end

  ##########################
  # Channel implementation #
  ##########################

  @impl Phoenix.Channel
  def join("device:" <> device_identifier, _params, socket) do
    # Socket already has authenticated user, just validate device access
    case authorize_device_access(socket.assigns.user, device_identifier) do
      {:ok, _device} ->
        {:ok, socket}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  @impl Phoenix.Channel
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "firmware_update", payload: %{percent: percent}},
        socket
      ) do
    # Forward the firmware update progress to the connected client
    push(socket, "firmware_update", %{percent: percent})

    {:noreply, socket}
  end

  def handle_info(msg, socket) do
    Logger.debug(
      "[ExternalDeviceListenerChannel] Unhandled handle_info message! - #{inspect(msg)}"
    )

    {:noreply, socket}
  end

  defp authorize_device_access(user, device_identifier) do
    with {:ok, device} <- Devices.get_by_identifier(device_identifier),
         org_user when not is_nil(org_user) <- Accounts.find_org_user_with_device(user, device.id) do
      {:ok, device}
    else
      _ -> {:error, :access_denied}
    end
  end
end
