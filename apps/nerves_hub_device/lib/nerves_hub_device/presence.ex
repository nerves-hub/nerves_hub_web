defmodule NervesHubDevice.Presence do
  @moduledoc """
  Implementation of Phoenix.Presence for Devices connected to NervesHub.

  # Example Usage

  ## List all connected devices for a product

      iex> NervesHubDevice.Presence.list("product:#\{product_id}:devices")

  ## Get a particular device's presence
      iex> device = %NervesHubWebCore.Devices.Device{...}
      iex> NervesHubDevice.Presence.find(device)
  """

  use Phoenix.Presence,
    otp_app: :nerves_hub_device,
    pubsub_server: NervesHubWeb.PubSub

  alias NervesHubWebCore.Devices.Device
  alias NervesHubDevice.Presence

  @allowed_fields [
    :connected_at,
    :console_available,
    :console_version,
    :firmware_metadata,
    :fwup_progress,
    :last_communication,
    :rebooting,
    :status,
    :update_available
  ]

  @typedoc """
  Status of the current connection.
  Human readable string, should not be used
  pragmatically
  """
  @type status :: String.t()

  @type device_id_string :: String.t()

  @type device_presence :: %{
          connected_at: pos_integer(),
          console_available: boolean(),
          console_version: Version.build(),
          firmware_metadata: NervesHubWebCore.Firmwares.FirmwareMetadata.t(),
          last_communication: DateTime.t(),
          status: status(),
          update_available: boolean()
        }

  @type presence_list :: %{optional(device_id_string) => device_presence}

  # because of how the `use` statement defines this function
  # and how the elaborate callback system works for presence,
  # this spec is not accepted by dialyzer, however when
  # one calls `list(product:#{product_id}:devices)` it will
  # return the `presence_list` value
  # @spec list(String.t()) :: presence_list()

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
  @spec device_status(Device.t()) :: status()
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
