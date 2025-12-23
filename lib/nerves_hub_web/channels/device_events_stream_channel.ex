defmodule NervesHubWeb.DeviceEventsStreamChannel do
  @moduledoc """
  Phoenix Channel for external services to subscribe to device updates.
  Currently only supports firmware update progress.

  External services can join device-specific channels using the topic pattern "device:\#{device_identifier}"
  """

  use Phoenix.Channel

  require Logger

  alias NervesHub.Accounts
  alias NervesHub.Products.ProductAPIKeyAccess
  alias NervesHubWeb.Helpers.Authorization

  @impl Phoenix.Channel
  def join("device:" <> device_identifier, _params, %{assigns: %{auth_type: :user_token, user: user}} = socket) do
    # Socket already has authenticated user, just validate device access
    if authorized?(user, device_identifier) do
      device_join(socket, device_identifier)
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  # No user, using a product api key
  def join(
        "device:" <> device_identifier,
        _params,
        %{assigns: %{auth_type: :product_api_key, product: product}} = socket
      ) do
    if ProductAPIKeyAccess.access_device?(product, device_identifier) do
      device_join(socket, device_identifier)
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  defp device_join(socket, device_identifier) do
    :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device_identifier}:internal")

    {:ok, socket}
  end

  @impl Phoenix.Channel
  def handle_info(%Phoenix.Socket.Broadcast{event: "fwup_progress", payload: %{percent: percent}}, socket) do
    # Forward the firmware update progress to the connected client
    push(socket, "firmware_update", %{percent: percent})

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
