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
  def join("device:console:" <> device_identifier, _params, socket) do
    # Socket already has authenticated user, just validate device access
    with true <- console_authorized?(socket.assigns.user, device_identifier),
         {:ok, %{id: device_id}} <- Devices.get_by_identifier(device_identifier) do
      :ok =
        Phoenix.PubSub.subscribe(NervesHub.PubSub, "user:console:#{device_id}")

      :ok =
        Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:console:#{device_id}:internal")

      {:ok, assign(socket, receive_console?: true)}
    else
      false ->
        {:error, %{reason: "unauthorized"}}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  def join("device:" <> device_identifier, _params, socket) do
    # Socket already has authenticated user, just validate device access
    if status_authorized?(socket.assigns.user, device_identifier) do
      :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device_identifier}:internal")

      {:ok, assign(socket, receive_status?: true)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl Phoenix.Channel
  def handle_info(
        %Broadcast{event: "fwup_progress", payload: %{percent: percent}},
        %{assigns: %{receive_status?: true}} = socket
      ) do
    # Forward the firmware update progress to the connected client
    push(socket, "firmware_update", %{percent: percent})

    {:noreply, socket}
  end

  def handle_info(
        %Broadcast{event: "connection:change", payload: %{status: status}},
        %{assigns: %{receive_status?: true}} = socket
      ) do
    push(socket, "connection_change", %{status: status})

    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: "connection:change"}, %{assigns: %{receive_status?: false}} = socket) do
    {:noreply, socket}
  end

  # Ignore any potential console message is not interested
  def handle_info(%Broadcast{topic: "user:console" <> _}, %{assigns: %{receive_console?: false}} = socket) do
    {:noreply, socket}
  end

  def handle_info(
        %Broadcast{topic: "user:console" <> _, event: "up", payload: %{"data" => data}},
        %{assigns: %{receive_console?: true}} = socket
      ) do
    push(socket, "console_raw", %{data: data})

    {:noreply, socket}
  end

  def handle_info(
        %Broadcast{topic: "user:console" <> _, event: "message", payload: payload},
        %{assigns: %{receive_console?: true}} = socket
      ) do
    push(socket, "console_message", payload)

    {:noreply, socket}
  end

  def handle_info(msg, socket) do
    Logger.debug("[DeviceEventsStreamChannel] Unhandled handle_info message! - #{inspect(msg)}")

    {:noreply, socket}
  end

  defp status_authorized?(user, device_identifier) do
    case Accounts.find_org_user_with_device_identifier(user, device_identifier) do
      nil ->
        false

      org_user ->
        Authorization.authorized?(:"device:view", org_user)
    end
  end

  defp console_authorized?(user, device_identifier) do
    case Accounts.find_org_user_with_device_identifier(user, device_identifier) do
      nil ->
        false

      org_user ->
        Authorization.authorized?(:"device:view", org_user)
    end
  end
end
