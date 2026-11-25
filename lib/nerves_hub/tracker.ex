defmodule NervesHub.Tracker do
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.PubSub
  alias NervesHub.Repo

  @doc """
  Tell internal listeners that the device is online, via a connection change
  """

  def heartbeat(%Device{} = device) do
    heartbeat(device.id)
  end

  def heartbeat(device_id) when is_integer(device_id) do
    _ = PubSub.broadcast(device_id, "connection:heartbeat", %{})

    :ok
  end

  def connecting(%Device{} = device) do
    connecting(device.id)
  end

  def connecting(device_id) when is_integer(device_id) do
    publish(device_id, "connecting")
  end

  def online(%Device{} = device) do
    online(device.id)
  end

  def online(device_id) when is_integer(device_id) do
    publish(device_id, "online")
  end

  @doc """
  Tell internal listeners that the device is offline, via a connection change.

  Given the connection that ended, the change also carries why
  (`disconnected_reason`) and, for a device that went to sleep, when it said
  it would be back (`expected_wake_at`), so a list of devices can show a
  sleeping one as asleep without reading the connection again. Listeners that
  only match on `status` are unaffected.
  """
  def offline(%Device{} = device) do
    offline(device.id)
  end

  def offline(%DeviceConnection{} = connection) do
    publish(connection.device_id, "offline", %{
      disconnected_reason: connection.disconnected_reason,
      disconnected_at: connection.disconnected_at,
      expected_wake_at: connection.expected_wake_at
    })
  end

  def offline(device_id) when is_integer(device_id) do
    publish(device_id, "offline")
  end

  defp publish(device_id, status, details \\ %{}) do
    _ = PubSub.broadcast(device_id, "connection:change", Map.put(details, :status, status))

    :ok
  end

  @doc """
  String version of `online?/1`
  """
  def connection_status(device) do
    if online?(device) do
      "online"
    else
      "offline"
    end
  end

  @doc """
  Check if a device is currently online

  Returns `true` if device's latest connections has a status of `:connected`,
  otherwise `false`.
  """
  def online?(%{latest_connection: %Ecto.Association.NotLoaded{}} = device),
    do: online?(Repo.preload(device, :latest_connection))

  def online?(%{latest_connection: %{status: :connected}}), do: true
  def online?(_), do: false
end
