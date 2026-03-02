defmodule NervesHubWeb.DeviceEventsStreamChannel do
  @moduledoc """
  Phoenix Channel for external services to subscribe to device updates.
  Currently only supports firmware update progress.

  External services can join device-specific channels using the topic pattern "device:\#{device_id}"
  """

  use Phoenix.Channel

  alias NervesHub.Accounts
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Devices
  alias NervesHubWeb.Helpers.Authorization
  alias Phoenix.Socket.Broadcast

  require Logger

  @impl Phoenix.Channel
  def join("device:" <> device_identifier, _params, socket) do
    # Socket already has authenticated user, just validate device access
    case authorized?(socket.assigns.user, device_identifier) do
      %OrgUser{} = org_user ->
        {:ok, device} = Devices.get_device_by_identifier(org_user.org, device_identifier)

        :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.id}:internal")

        {:ok, socket}

      _ ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  def join(org_name_and_device_identifier, _params, socket) do
    ["org", org_name, "device", device_identifier] = String.split(org_name_and_device_identifier, ":")

    # Socket already has authenticated user, just validate device access
    case authorized?(socket.assigns.user, org_name, device_identifier) do
      %OrgUser{} = org_user ->
        {:ok, device} = Devices.get_device_by_identifier(org_user.org, device_identifier)

        :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.id}:internal")

        {:ok, socket}

      _ ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  @impl Phoenix.Channel
  def handle_info(%Broadcast{event: "fwup_progress", payload: %{percent: percent}}, socket) do
    # Forward the firmware update progress to the connected client
    push(socket, "firmware_update", %{percent: percent})

    {:noreply, socket}
  end

  def handle_info(msg, socket) do
    Logger.debug("[DeviceEventsStreamChannel] Unhandled handle_info message! - #{inspect(msg)}")

    {:noreply, socket}
  end

  defp authorized?(user, device_identifier) do
    Application.get_env(:nerves_hub, :platform_unique_device_identifiers) &&
      case Accounts.find_org_user_with_device_identifier(user, device_identifier) do
        nil ->
          false

        org_user ->
          Authorization.authorized?(:"device:view", org_user) && org_user
      end
  end

  defp authorized?(user, org_name, device_identifier) do
    with %OrgUser{} = org_user <- Accounts.find_org_user_with_device_identifier(user, device_identifier),
         true <- org_user.org.name == org_name,
         true <- Authorization.authorized?(:"device:view", org_user) do
      org_user
    else
      _ ->
        false
    end
  end
end
