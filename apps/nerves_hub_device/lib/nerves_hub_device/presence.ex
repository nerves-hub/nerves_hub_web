defmodule NervesHubDevice.Presence do
  use Phoenix.Presence,
    otp_app: :nerves_hub_device,
    pubsub_server: NervesHubWeb.PubSub

  alias NervesHubCore.Devices.Device
  alias NervesHubDevice.Presence

  def fetch("devices:" <> _, entries) do
    Enum.reduce(entries, %{}, fn
      {key, %{metas: [%{last_known_firmware_id: nil}]} = val}, acc ->
        Map.put(acc, key, Map.put(val, :status, "offline"))

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
  - `"offline"` - The device does not have a `:last_known_firmware_id` or is not connected to
    Presence
  """
  @spec device_status(Device.t()) :: Strint.t()
  def device_status(%Device{id: device_id, last_known_firmware_id: lkf_id, org_id: org_id})
      when not is_nil(lkf_id) do
    "devices:#{org_id}"
    |> Presence.list()
    |> Map.get("#{device_id}")
    |> case do
      %{metas: [%{update_available: true}]} -> "update pending"
      _ -> "online"
    end
  end

  def device_status(_) do
    "offline"
  end
end
