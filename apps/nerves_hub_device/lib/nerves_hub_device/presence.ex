defmodule NervesHubDevice.Presence do
  use Phoenix.Presence,
    otp_app: :nerves_hub_device,
    pubsub_server: NervesHubWeb.PubSub

  alias NervesHubWebCore.Devices.Device
  alias NervesHubDevice.Presence

  @allowed_fields [
    :connected_at,
    :console_available,
    :firmware_metadata,
    :fwup_progress,
    :last_communication,
    :rebooting,
    :status,
    :update_available
  ]

  def fetch("product:" <> topic, entries) do
    case String.split(topic, ":", trim: true) do
      [_product_id, "devices"] ->
        for {key, entry} <- entries, into: %{}, do: {key, merge_metas(entry)}

      _ ->
        entries
    end
  end

  def fetch(_, entries), do: entries

  def find(device, default \\ nil)

  def find(%Device{id: device_id, product_id: product_id}, default) do
    "product:#{product_id}:devices"
    |> Presence.list()
    |> Map.get("#{device_id}", default)
  end

  def find(_, default), do: default

  @doc """
  Return the status of a device.

  ## Statuses

  - `"online"` - The device has `:firmware_metadata` and is connected to Presence
  - `"update pending"` - The device has `:firmware_metadata`, is connected to presence, and
    its presence meta includes `update_available: true`
  - `"offline"` - The device is not connected to Presence
  """
  @spec device_status(Device.t()) :: String.t()
  def device_status(%Device{} = device) do
    case find(device) do
      nil -> "offline"
      %{status: status} -> status
    end
  end

  def device_status(_) do
    "offline"
  end

  defp merge_metas(%{metas: metas}) do
    # The most current meta is head of the list so we
    # accumulate that first and merge everthing else into it
    Enum.reduce(metas, %{}, &Map.merge(&1, &2))
    |> Map.take(@allowed_fields)
    |> case do
      %{status: _status} = e -> e
      %{update_available: true} = e -> Map.put(e, :status, "update pending")
      %{rebooting: true} = e -> Map.put(e, :status, "rebooting")
      %{fwup_progress: _progress} = e -> Map.put(e, :status, "updating")
      e -> Map.put(e, :status, "online")
    end
  end

  defp merge_metas(unknown), do: unknown
end
