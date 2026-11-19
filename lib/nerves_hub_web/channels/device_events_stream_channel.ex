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
  alias NervesHub.Accounts.TwoFactor
  alias NervesHub.Accounts.User
  alias NervesHub.Devices
  alias NervesHub.Devices.PubSub
  alias NervesHub.Products.ApiKey
  alias NervesHubWeb.Helpers.Authorization
  alias Phoenix.Socket.Broadcast

  require Logger

  @impl Phoenix.Channel
  def join("device:" <> device_identifier, _params, socket) do
    # The socket is already authenticated, so this only checks device access.
    scope = socket.assigns.current_scope

    case authorized_device(scope, device_identifier) do
      {:ok, device} ->
        :ok = PubSub.subscribe(device.id)
        :ok = subscribe_membership(scope, device)
        :ok = AccessPubSub.subscribe_device_access(device.id)

        {:ok, assign(socket, :device_identifier, device_identifier)}

      :error ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  # A product API key has no membership to watch. Deactivating it, or editing
  # the custom role it holds, disconnects the socket instead; see
  # `NervesHub.Products.ApiKeys.deactivate/3` and `disconnect_holders/1`.
  defp subscribe_membership(%Scope{user: %User{} = user}, device),
    do: AccessPubSub.subscribe_membership(device.org_id, user.id)

  defp subscribe_membership(%Scope{}, _device), do: :ok

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

  # The role in the device's org changed, a member was removed from it, the org
  # started requiring two-factor, or the device's tags changed. Checked the same
  # way as on join, so whoever couldn't subscribe now doesn't stay subscribed.
  def handle_info({event, _id}, socket) when event in [:org_membership_changed, :device_access_changed] do
    case authorized_device(socket.assigns.current_scope, socket.assigns.device_identifier) do
      {:ok, _device} -> {:noreply, socket}
      :error -> {:stop, {:shutdown, :closed}, socket}
    end
  end

  def handle_info(msg, socket) do
    Logger.debug("[DeviceEventsStreamChannel] Unhandled handle_info message! - #{inspect(msg)}")

    {:noreply, socket}
  end

  # Looked up through whoever is acting, so a device their role can't see isn't
  # found. A key's scope also carries its product, which is what keeps it to
  # that product's devices.
  defp authorized_device(%Scope{api_key: %ApiKey{}} = scope, device_identifier) do
    with {:ok, device} <- Devices.get_by_identifier(scope, device_identifier),
         true <- Authorization.authorized?(:"device:view", scope) do
      {:ok, device}
    else
      _ -> :error
    end
  end

  defp authorized_device(%Scope{user: %User{} = user}, device_identifier) do
    with {:ok, device} <- Devices.get_by_identifier(Scope.for_user(user), device_identifier),
         %OrgUser{} = org_user <- Accounts.find_org_user_with_device(user, device.id),
         true <- Authorization.authorized?(:"device:view", org_user),
         true <- TwoFactor.meets_org_requirement?(device.org_id, user) do
      {:ok, device}
    else
      _ -> :error
    end
  end

  defp authorized_device(%Scope{}, _device_identifier), do: :error
end
