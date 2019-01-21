defmodule NervesHubDevice.Presence do
  use Phoenix.Presence,
    otp_app: :nerves_hub_device,
    pubsub_server: NervesHubWeb.PubSub

  alias NervesHubWebCore.Devices.Device
  alias NervesHubDevice.Presence

  def fetch("devices:" <> _, entries) do
    Enum.reduce(entries, %{}, fn
      {key, %{metas: [%{update_available: true}]} = val}, acc ->
        Map.put(acc, key, Map.put(val, :status, "update pending"))

      {key, val}, acc ->
        Map.put(acc, key, Map.put(val, :status, "online"))
    end)
  end

  def fetch(_, entries), do: entries

  @doc """
  Return the status of a device.

  ## Statuses

  - `"online"` - The device has a `:last_known_firmware_id` and is connected to Presence
  - `"update pending"` - The device has a `:last_known_firmware_id`, is connected to presence, and
    its presence meta includes `update_available: true`
  - `"offline"` - The device is not connected to Presence
  """
  @spec device_status(Device.t()) :: String.t()
  def device_status(%Device{id: device_id, org_id: org_id}) do
    "devices:#{org_id}"
    |> Presence.list()
    |> Map.get("#{device_id}")
    |> case do
      nil -> "offline"
      %{metas: [%{update_available: true}]} -> "update pending"
      %{} -> "online"
    end
  end

  def device_status(_) do
    "offline"
  end
end
